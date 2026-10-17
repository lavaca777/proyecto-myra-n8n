# =====================================================================
# Abre el tunel de Cloudflare, actualiza WEBHOOK_URL (en .env y en la
# sesion) y reinicia n8n para que Telegram use la URL publica.
#
# Uso: .\scripts\tunnel.ps1
# Si el stack ya esta levantado, este es el script que necesitas.
# Si quieres levantar todo desde cero, usa .\scripts\dev.ps1
#
# Ctrl+C cierra el tunel. Los contenedores siguen corriendo.
# =====================================================================

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_env.ps1"

$root = Get-ProjectRoot
Set-Location $root

Assert-Docker
Import-DotEnv (Join-Path $root '.env')
Ensure-PgVolume

$existing = Get-Process cloudflared -ErrorAction SilentlyContinue
if ($existing) {
    Write-Warning 'Hay un cloudflared corriendo. Si es de una sesion anterior, cierrala con Ctrl+C; si no, se creara otro tunel.'
}

Write-Host 'Iniciando tunel de Cloudflare...' -ForegroundColor Cyan
$tunnel = Start-CloudflareTunnel -LogPath (Join-Path $root 'cloudflared.log')
$publicUrl = Set-WebhookUrl -EnvPath (Join-Path $root '.env') -Url $tunnel.Url

Write-Host "Tunel activo: $publicUrl" -ForegroundColor Green
Write-Host 'Reiniciando n8n con la URL publica...' -ForegroundColor Yellow
docker compose up -d --force-recreate n8n

if (Wait-PostgresHealthy -TimeoutSeconds 30) {
    Start-Sleep -Seconds 2
    & (Join-Path $PSScriptRoot 'db-migrate.ps1')
} else {
    Write-Warning 'PostgreSQL no reporto healthy. Revisa: docker compose logs postgres'
}

Write-Host ''
Write-Host '========================================================' -ForegroundColor Cyan
Write-Host ' n8n local:       http://localhost:5678' -ForegroundColor Green
Write-Host " Webhook publico: $publicUrl" -ForegroundColor Green
Write-Host ' Deja esta ventana abierta. Ctrl+C cierra el tunel.' -ForegroundColor Yellow
Write-Host '========================================================' -ForegroundColor Cyan

try {
    while ($true) { Start-Sleep -Seconds 2 }
}
finally {
    Write-Host ''
    Write-Host 'Cerrando tunel de Cloudflare...' -ForegroundColor Red
    Stop-Process -Id $tunnel.Process.Id -Force -ErrorAction SilentlyContinue
}
