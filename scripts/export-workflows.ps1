# =====================================================================
# Exporta TODOS los workflows de n8n a n8n/workflows/*.json.
# Se ejecuta despues de cada cambio en la UI y antes de cada commit.
#
# En Windows, n8n mantiene SQLite bloqueado mientras corre. Por eso el
# script detiene el contenedor, exporta con un contenedor temporal y lo
# vuelve a levantar.
#
# Uso: .\scripts\export-workflows.ps1
# =====================================================================

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_env.ps1"

$root = Get-ProjectRoot
Set-Location $root

Assert-Docker

$workflowsDir = Join-Path $root 'n8n\workflows'
$exportDir = Join-Path $workflowsDir '.export-tmp'
$containerTmp = '/workflows/.export-tmp'
$wasRunning = Test-ContainerRunning -Name 'myra-n8n'

New-Item -ItemType Directory -Force -Path $workflowsDir | Out-Null

try {
    if ($wasRunning) {
        Write-Host 'Deteniendo n8n para liberar SQLite...' -ForegroundColor Yellow
        docker compose stop n8n | Out-Null
    }

    Write-Host 'Exportando workflows...' -ForegroundColor Cyan

    docker compose run --rm --no-deps --entrypoint sh n8n -c `
        "rm -rf $containerTmp && mkdir -p $containerTmp && n8n export:workflow --all --separate --output=$containerTmp"

    if ($LASTEXITCODE -ne 0) {
        throw 'Fallo el export de workflows. Revisa los logs de n8n.'
    }

    $exported = @(Get-ChildItem -Path $exportDir -Filter '*.json' -File -ErrorAction SilentlyContinue)
    if ($exported.Count -le 0) {
        throw 'El export no genero archivos JSON. No se toco la carpeta local.'
    }

    # Solo despues de un export exitoso se reemplazan los archivos locales.
    Get-ChildItem -Path $workflowsDir -Filter '*.json' -File | Remove-Item -Force

    function ConvertTo-Slug {
        param([string]$Text)
        $normalized = $Text.Normalize([Text.NormalizationForm]::FormD)
        $normalized = -join ($normalized.ToCharArray() | Where-Object {
            [Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne [Globalization.UnicodeCategory]::NonSpacingMark
        })
        return ($normalized.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
    }

    foreach ($file in $exported) {
        try {
            $wf = Get-Content -Path $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        } catch {
            continue
        }

        $slug = ConvertTo-Slug $wf.name
        if ([string]::IsNullOrWhiteSpace($slug)) { $slug = $file.BaseName }

        $target = Join-Path $workflowsDir ($slug + '.json')
        if (Test-Path $target) {
            $target = Join-Path $workflowsDir ($slug + '-' + $file.BaseName.Substring(0, 6) + '.json')
        }
        Move-Item -Path $file.FullName -Destination $target
    }

    Write-Host "Listo: $($exported.Count) workflow(s) exportado(s) a $workflowsDir" -ForegroundColor Green
    Get-ChildItem -Path $workflowsDir -Filter '*.json' | ForEach-Object {
        Write-Host "  - $($_.Name)" -ForegroundColor DarkGray
    }
}
finally {
    if (Test-Path $exportDir) {
        Remove-Item -Path $exportDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($wasRunning) {
        Write-Host 'Levantando n8n...' -ForegroundColor Yellow
        docker compose start n8n | Out-Null
    }
}
