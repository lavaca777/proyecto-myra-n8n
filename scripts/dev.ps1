# =====================================================================
# Modo desarrollo completo (equivalente al antiguo start-all.ps1):
#   1. Abre el tunel de Cloudflare.
#   2. Actualiza WEBHOOK_URL en .env y en la sesion.
#   3. Levanta PostgreSQL + n8n YA con la URL publica.
#   4. Aplica migraciones.
#   5. Mantiene el tunel activo.
#
# Uso: .\scripts\dev.ps1
# Ctrl+C cierra el tunel. Los contenedores siguen corriendo.
# =====================================================================

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_env.ps1"

$root = Get-ProjectRoot
Set-Location $root

Assert-Docker
Import-DotEnv (Join-Path $root '.env')
Ensure-PgVolume
Stop-LegacyContainers

$existing = Get-Process cloudflared -ErrorAction SilentlyContinue
if ($existing) {
    Write-Warning 'Hay un cloudflared corriendo. Si es de una sesion anterior, cierrala con Ctrl+C; si no, se creara otro tunel.'
}

Write-Host 'Iniciando tunel de Cloudflare...' -ForegroundColor Cyan
$tunnel = Start-CloudflareTunnel -LogPath (Join-Path $root 'cloudflared.log')
$publicUrl = Set-WebhookUrl -EnvPath (Join-Path $root '.env') -Url $tunnel.Url

Write-Host "Tunel activo: $publicUrl" -ForegroundColor Green
Write-Host 'Levantando PostgreSQL + n8n con la URL publica...' -ForegroundColor Cyan
docker compose up -d

if (-not (Wait-PostgresHealthy -TimeoutSeconds 30)) {
    Write-Warning 'PostgreSQL no reporto healthy en 30 s. Revisa: docker compose logs postgres'
} else {
    Start-Sleep -Seconds 2
    & (Join-Path $PSScriptRoot 'db-migrate.ps1')
}

Write-Host ''
docker compose ps
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
