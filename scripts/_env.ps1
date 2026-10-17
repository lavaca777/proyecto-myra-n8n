# =====================================================================
# Utilidades compartidas por los scripts de PowerShell.
# Se importa con:  . "$PSScriptRoot\_env.ps1"
# =====================================================================

function Get-ProjectRoot {
    return (Split-Path -Parent $PSScriptRoot)
}

function Import-DotEnv {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        throw "No existe $Path. Copia .env.example a .env y completa los valores."
    }

    Get-Content -Path $Path | ForEach-Object {
        $line = $_.Trim()
        if ($line -eq '' -or $line.StartsWith('#')) { return }
        $idx = $line.IndexOf('=')
        if ($idx -lt 1) { return }
        $name = $line.Substring(0, $idx).Trim()
        $value = $line.Substring($idx + 1).Trim().Trim('"').Trim("'")
        [Environment]::SetEnvironmentVariable($name, $value, 'Process')
    }
}

function Assert-Docker {
    docker info *> $null
    if ($LASTEXITCODE -ne 0) {
        throw 'Docker Desktop no esta corriendo o no responde. Abrelo y vuelve a intentar.'
    }
}

function Test-ContainerRunning {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $names = docker ps --format '{{.Names}}' 2>$null
    return ($names -contains $Name)
}

function Ensure-PgVolume {
    docker volume inspect myra_db_pg_data *> $null
    if ($LASTEXITCODE -ne 0) {
        docker volume create myra_db_pg_data | Out-Null
    }
}

function Wait-PostgresHealthy {
    param(
        [int]$TimeoutSeconds = 30
    )

    for ($i = 0; $i -lt $TimeoutSeconds; $i++) {
        $status = docker inspect --format '{{.State.Health.Status}}' myra-postgres 2>$null
        if ($status -eq 'healthy') { return $true }
        Start-Sleep -Seconds 1
    }
    return $false
}

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}
