# =====================================================================
# Levanta un tunel rapido de Cloudflare contra n8n, actualiza WEBHOOK_URL
# en .env y reinicia n8n para que Telegram use la nueva URL.
#
# Uso: .\scripts\tunnel.ps1
# Deja la ventana abierta mientras pruebes el bot. Ctrl+C cierra el tunel.
# =====================================================================

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_env.ps1"

$root = Get-ProjectRoot
Set-Location $root

Assert-Docker
Import-DotEnv (Join-Path $root '.env')

if (-not (Get-Command cloudflared -ErrorAction SilentlyContinue)) {
    throw 'No se encontro cloudflared en el PATH. Instalalo o agregalo al PATH.'
}

$envPath = Join-Path $root '.env'
$logPath = Join-Path $root 'cloudflared.log'
if (Test-Path $logPath) { Remove-Item $logPath -Force }

Write-Host 'Iniciando tunel de Cloudflare...' -ForegroundColor Cyan
$tunnel = Start-Process -FilePath 'cloudflared' `
    -ArgumentList 'tunnel', '--url', 'http://localhost:5678' `
    -RedirectStandardError $logPath `
    -NoNewWindow -PassThru

$url = $null
$timeout = 30

while ($timeout -gt 0 -and [string]::IsNullOrEmpty($url)) {
    if ($tunnel.HasExited) {
        throw "cloudflared termino inesperadamente (codigo $($tunnel.ExitCode)). Revisa $logPath."
    }
    Start-Sleep -Seconds 1
    $timeout--
    if (Test-Path $logPath) {
        $content = Get-Content $logPath -Raw
        if ($content -match 'https://[a-zA-Z0-9-]+\.trycloudflare\.com') {
            $url = $Matches[0]
        }
    }
}

if ([string]::IsNullOrEmpty($url)) {
    Stop-Process -Id $tunnel.Id -Force -ErrorAction SilentlyContinue
    throw 'No se pudo obtener la URL de Cloudflare. Revisa cloudflared.log.'
}

$urlWithSlash = if ($url.EndsWith('/')) { $url } else { "$url/" }

Write-Host "Tunel activo: $urlWithSlash" -ForegroundColor Green

# Actualizar WEBHOOK_URL sin tocar el resto del .env
$envContent = Get-Content $envPath -Raw
if ($envContent -match '(?m)^WEBHOOK_URL=') {
    $envContent = $envContent -replace '(?m)^WEBHOOK_URL=.*$', "WEBHOOK_URL=$urlWithSlash"
} else {
    $envContent = $envContent.TrimEnd() + "`nWEBHOOK_URL=$urlWithSlash`n"
}
Write-Utf8NoBom -Path $envPath -Content $envContent

Write-Host 'Reiniciando n8n con la nueva URL...' -ForegroundColor Yellow
docker compose up -d --force-recreate n8n

Write-Host ''
Write-Host '========================================================' -ForegroundColor Cyan
Write-Host " Webhook publico: $urlWithSlash" -ForegroundColor Green
Write-Host ' n8n local:       http://localhost:5678' -ForegroundColor White
Write-Host ' Deja esta ventana abierta. Ctrl+C para cerrar el tunel.' -ForegroundColor Yellow
Write-Host '========================================================' -ForegroundColor Cyan

try {
    while ($true) { Start-Sleep -Seconds 2 }
}
finally {
    Write-Host ''
    Write-Host 'Cerrando tunel de Cloudflare...' -ForegroundColor Red
    Stop-Process -Id $tunnel.Id -Force -ErrorAction SilentlyContinue
}
