# =====================================================================
# Consola SQL rapida contra PostgreSQL.
#
# Uso interactivo:
#   .\scripts\psql.ps1
#
# Una consulta:
#   .\scripts\psql.ps1 -Query "SELECT * FROM v_gastos_detalle LIMIT 5;"
# =====================================================================

param(
    [string]$Query
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_env.ps1"

$root = Get-ProjectRoot
Set-Location $root

Assert-Docker
Import-DotEnv (Join-Path $root '.env')

if (-not (Test-ContainerRunning -Name 'myra-postgres')) {
    throw 'El contenedor myra-postgres no esta corriendo. Ejecuta .\scripts\start.ps1'
}

if ($Query) {
    docker exec -i myra-postgres psql -U $env:DB_USER -d $env:DB_NAME -c $Query
} else {
    docker exec -it myra-postgres psql -U $env:DB_USER -d $env:DB_NAME
}
