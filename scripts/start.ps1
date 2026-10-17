# =====================================================================
# Levanta PostgreSQL + n8n y aplica migraciones pendientes.
# Uso: .\scripts\start.ps1
# =====================================================================

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_env.ps1"

$root = Get-ProjectRoot
Set-Location $root

Assert-Docker
Import-DotEnv (Join-Path $root '.env')

# Detener el stack anterior si quedo corriendo (no borra nada).
Stop-LegacyContainers

Ensure-PgVolume

Write-Host "Levantando PostgreSQL + n8n..." -ForegroundColor Cyan
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
Write-Host ' n8n:        http://localhost:5678' -ForegroundColor Green
Write-Host ' PostgreSQL: localhost:5433 (usuario ' -NoNewline
Write-Host $env:DB_USER -NoNewline -ForegroundColor Yellow
Write-Host ', base ' -NoNewline
Write-Host $env:DB_NAME -NoNewline -ForegroundColor Yellow
Write-Host ')'
Write-Host ' Telegram:   ejecuta .\scripts\tunnel.ps1 para obtener URL publica' -ForegroundColor White
Write-Host '========================================================' -ForegroundColor Cyan
