# =====================================================================
# Aplica las migraciones pendientes de db/migrations/.
# Es idempotente: si un archivo ya esta en schema_migrations, lo salta.
#
# Uso: .\scripts\db-migrate.ps1
# =====================================================================

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_env.ps1"

$root = Get-ProjectRoot
Set-Location $root

Assert-Docker
Import-DotEnv (Join-Path $root '.env')

Ensure-PgVolume

Write-Host 'Asegurando PostgreSQL...' -ForegroundColor Cyan
docker compose up -d postgres | Out-Null

if (-not (Wait-PostgresHealthy -TimeoutSeconds 30)) {
    throw 'PostgreSQL no esta healthy. Revisa: docker compose logs postgres'
}

$migrationsDir = Join-Path $root 'db\migrations'
$files = Get-ChildItem -Path $migrationsDir -Filter '*.sql' | Sort-Object Name

if ($files.Count -eq 0) {
    Write-Host 'No hay migraciones.' -ForegroundColor Yellow
    return
}

# Leer migraciones aplicadas. Si la tabla no existe, se asume lista vacia.
# Se usa to_regclass para no provocar un error de psql cuando la tabla aun no existe.
$applied = @()
$tableExistsRaw = docker compose exec -T postgres psql -U $env:DB_USER -d $env:DB_NAME `
    -tAc "SELECT to_regclass('public.schema_migrations') IS NOT NULL;"
$tableExists = $false
if ($tableExistsRaw) { $tableExists = ($tableExistsRaw.Trim() -eq 't') }

if ($tableExists) {
    $appliedRaw = docker compose exec -T postgres psql -U $env:DB_USER -d $env:DB_NAME `
        -tAc "SELECT filename FROM schema_migrations"
    if ($appliedRaw) {
        $applied = $appliedRaw -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    }
}

foreach ($file in $files) {
    if ($applied -contains $file.Name) {
        Write-Host "  SKIP  $($file.Name)" -ForegroundColor DarkGray
        continue
    }

    Write-Host "  APPLY $($file.Name)" -ForegroundColor Yellow

    docker compose cp $file.FullName "postgres:/tmp/$($file.Name)" | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "No se pudo copiar $($file.Name) al contenedor."
    }

    docker compose exec -T postgres psql -U $env:DB_USER -d $env:DB_NAME `
        -v ON_ERROR_STOP=1 -f "/tmp/$($file.Name)"

    if ($LASTEXITCODE -ne 0) {
        throw "Fallo la migracion $($file.Name). Revisa el error de psql."
    }

    # Registro defensivo: las migraciones actuales ya se registran solas.
    $escaped = $file.Name.Replace("'", "''")
    docker compose exec -T postgres psql -U $env:DB_USER -d $env:DB_NAME `
        -c "INSERT INTO schema_migrations (filename) VALUES ('$escaped') ON CONFLICT DO NOTHING;" | Out-Null

    docker compose exec -T postgres rm -f "/tmp/$($file.Name)" | Out-Null
}

Write-Host 'Migraciones al dia.' -ForegroundColor Green
