# =====================================================================
# Exporta TODOS los workflows de n8n a n8n/workflows/*.json.
# Se ejecuta despues de cada cambio en la UI y antes de cada commit.
#
# Uso: .\scripts\export-workflows.ps1
# =====================================================================

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_env.ps1"

$root = Get-ProjectRoot
Set-Location $root

Assert-Docker

if (-not (Test-ContainerRunning -Name 'myra-n8n')) {
    throw 'El contenedor myra-n8n no esta corriendo. Ejecuta .\scripts\start.ps1'
}

$workflowsDir = Join-Path $root 'n8n\workflows'
New-Item -ItemType Directory -Force -Path $workflowsDir | Out-Null

Write-Host 'Exportando workflows a /tmp/wf-export...' -ForegroundColor Cyan

docker compose exec -T n8n sh -lc 'rm -rf /tmp/wf-export && mkdir -p /tmp/wf-export' | Out-Null
docker compose exec -T n8n n8n export:workflow --all --separate --output=/tmp/wf-export

if ($LASTEXITCODE -ne 0) {
    throw 'Fallo el export de workflows. Revisa los logs de n8n.'
}

$countRaw = docker compose exec -T n8n sh -lc 'ls -1 /tmp/wf-export/*.json 2>/dev/null | wc -l'
$count = 0
if ($countRaw) { $count = [int]$countRaw.Trim() }

if ($count -le 0) {
    throw 'El export no genero archivos JSON. No se toco la carpeta local.'
}

# Solo despues de un export exitoso se reemplazan los archivos locales.
Get-ChildItem -Path $workflowsDir -Filter '*.json' -File | Remove-Item -Force

docker compose cp 'n8n:/tmp/wf-export/.' $workflowsDir | Out-Null
docker compose exec -T n8n rm -rf /tmp/wf-export | Out-Null

# n8n exporta con el ID como nombre. Renombrar a kebab-case segun el nombre real.
function ConvertTo-Slug {
    param([string]$Text)
    $normalized = $Text.Normalize([Text.NormalizationForm]::FormD)
    $normalized = -join ($normalized.ToCharArray() | Where-Object {
        [Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne [Globalization.UnicodeCategory]::NonSpacingMark
    })
    return ($normalized.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
}

foreach ($file in (Get-ChildItem -Path $workflowsDir -Filter '*.json' -File)) {
    try {
        $wf = Get-Content -Path $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        continue
    }

    $slug = ConvertTo-Slug $wf.name
    if ([string]::IsNullOrWhiteSpace($slug)) { $slug = $file.BaseName }

    $target = Join-Path $workflowsDir ($slug + '.json')
    if ($target -eq $file.FullName) { continue }
    if (Test-Path $target) {
        $target = Join-Path $workflowsDir ($slug + '-' + $file.BaseName.Substring(0, 6) + '.json')
    }
    Move-Item -Path $file.FullName -Destination $target
}

Write-Host "Listo: $count workflow(s) exportado(s) a $workflowsDir" -ForegroundColor Green
Get-ChildItem -Path $workflowsDir -Filter '*.json' | ForEach-Object {
    Write-Host "  - $($_.Name)" -ForegroundColor DarkGray
}
