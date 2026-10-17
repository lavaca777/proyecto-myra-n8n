# =====================================================================
# Respaldo completo:
#   1. pg_dump de PostgreSQL
#   2. export de workflows a n8n/workflows/
#   3. export de credenciales de n8n (cifradas con la encryption key)
#
# Uso: .\scripts\backup.ps1
# Retencion: 14 dias.
# =====================================================================

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_env.ps1"

$root = Get-ProjectRoot
Set-Location $root

Assert-Docker
Import-DotEnv (Join-Path $root '.env')

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$backupDir = Join-Path $root 'db\backups'
New-Item -ItemType Directory -Force -Path $backupDir | Out-Null

# --- PostgreSQL ---
if (-not (Test-ContainerRunning -Name 'myra-postgres')) {
    Write-Host 'Levantando PostgreSQL para el respaldo...' -ForegroundColor Yellow
    Ensure-PgVolume
    docker compose up -d postgres | Out-Null
    if (-not (Wait-PostgresHealthy -TimeoutSeconds 30)) {
        throw 'PostgreSQL no esta healthy. No se puede respaldar.'
    }
}

$dumpName = "myra_$stamp.dump"
Write-Host "Respaldando PostgreSQL ($dumpName)..." -ForegroundColor Cyan
docker compose exec -T postgres pg_dump -U $env:DB_USER -d $env:DB_NAME -Fc -f "/tmp/$dumpName"
if ($LASTEXITCODE -ne 0) { throw 'Fallo pg_dump.' }

docker compose cp "postgres:/tmp/$dumpName" (Join-Path $backupDir $dumpName) | Out-Null
docker compose exec -T postgres rm -f "/tmp/$dumpName" | Out-Null

# --- n8n ---
if (Test-ContainerRunning -Name 'myra-n8n') {
    Write-Host 'Exportando workflows...' -ForegroundColor Cyan
    & (Join-Path $PSScriptRoot 'export-workflows.ps1')

    $credName = "credentials_$stamp.json"
    Write-Host "Respaldando credenciales de n8n ($credName)..." -ForegroundColor Cyan
    docker compose exec -T n8n n8n export:credentials --all --output="/tmp/$credName"
    if ($LASTEXITCODE -eq 0) {
        docker compose cp "n8n:/tmp/$credName" (Join-Path $backupDir $credName) | Out-Null
        docker compose exec -T n8n rm -f "/tmp/$credName" | Out-Null
    } else {
        Write-Warning 'No se pudieron exportar las credenciales de n8n.'
    }
} else {
    Write-Warning 'n8n no esta corriendo: se omite el export de workflows y credenciales.'
}

# --- Retencion ---
$limit = (Get-Date).AddDays(-14)
Get-ChildItem -Path $backupDir -File |
    Where-Object { $_.LastWriteTime -lt $limit } |
    ForEach-Object {
        Write-Host "Eliminando respaldo antiguo: $($_.Name)" -ForegroundColor DarkGray
        Remove-Item $_.FullName -Force
    }

Write-Host ''
Write-Host 'Respaldo completado:' -ForegroundColor Green
Get-ChildItem -Path $backupDir -File | Sort-Object LastWriteTime -Descending | Select-Object -First 5 |
    ForEach-Object { Write-Host "  $($_.Name)  ($([math]::Round($_.Length / 1MB, 2)) MB)" }
