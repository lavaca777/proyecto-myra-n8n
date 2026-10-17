# =====================================================================
# Detiene los contenedores SIN borrar datos.
# Uso: .\scripts\stop.ps1
# =====================================================================

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_env.ps1"

$root = Get-ProjectRoot
Set-Location $root

Assert-Docker

Write-Host 'Deteniendo PostgreSQL + n8n...' -ForegroundColor Yellow
docker compose down

Write-Host ''
Write-Host 'Listo. Los datos se conservan en:' -ForegroundColor Green
Write-Host "  - $root\n8n\data"
Write-Host '  - volumen Docker myra_db_pg_data'
