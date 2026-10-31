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
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    docker info *> $null
    $dockerExitCode = $LASTEXITCODE
    $ErrorActionPreference = $oldPreference

    if ($dockerExitCode -ne 0) {
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
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    # "docker volume create" es idempotente: si ya existe, no falla.
    docker volume create myra_db_pg_data *> $null
    $dockerExitCode = $LASTEXITCODE
    $ErrorActionPreference = $oldPreference

    if ($dockerExitCode -ne 0) {
        throw 'No se pudo crear el volumen myra_db_pg_data. Revisa Docker Desktop.'
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

function Stop-LegacyContainers {
    $oldContainers = @('myra_db-postgres-1', 'myra_db-n8n-1', 'n8n_local_myra')
    foreach ($name in $oldContainers) {
        if (Test-ContainerRunning -Name $name) {
            Write-Host "Deteniendo contenedor anterior: $name" -ForegroundColor Yellow
            docker stop $name | Out-Null
        }
    }
}

function Start-CloudflareTunnel {
    param(
        [Parameter(Mandatory = $true)][string]$LogPath,
        [int]$TimeoutSeconds = 30
    )

    if (-not (Get-Command cloudflared -ErrorAction SilentlyContinue)) {
        throw 'No se encontro cloudflared en el PATH. Instalalo o agregalo al PATH.'
    }

    if (Test-Path $LogPath) { Remove-Item $LogPath -Force }

    $process = Start-Process -FilePath 'cloudflared' `
        -ArgumentList 'tunnel', '--url', 'http://localhost:5678' `
        -RedirectStandardError $LogPath `
        -NoNewWindow -PassThru

    $url = $null
    $timeout = $TimeoutSeconds

    while ($timeout -gt 0 -and [string]::IsNullOrEmpty($url)) {
        if ($process.HasExited) {
            throw "cloudflared termino inesperadamente (codigo $($process.ExitCode)). Revisa $LogPath."
        }
        Start-Sleep -Seconds 1
        $timeout--
        if (Test-Path $LogPath) {
            $content = Get-Content $LogPath -Raw
            if ($content -match 'https://[a-zA-Z0-9-]+\.trycloudflare\.com') {
                $url = $Matches[0]
            }
        }
    }

    if ([string]::IsNullOrEmpty($url)) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        throw 'No se pudo obtener la URL de Cloudflare. Revisa cloudflared.log.'
    }

    return [pscustomobject]@{
        Process = $process
        Url     = $url
        LogPath = $LogPath
    }
}

function Set-WebhookUrl {
    param(
        [Parameter(Mandatory = $true)][string]$EnvPath,
        [Parameter(Mandatory = $true)][string]$Url
    )

    $urlWithSlash = if ($Url.EndsWith('/')) { $Url } else { "$Url/" }

    $content = Get-Content -Path $EnvPath -Raw
    if ($content -match '(?m)^WEBHOOK_URL=') {
        $content = $content -replace '(?m)^WEBHOOK_URL=.*$', "WEBHOOK_URL=$urlWithSlash"
    } else {
        $content = $content.TrimEnd() + "`nWEBHOOK_URL=$urlWithSlash`n"
    }
    Write-Utf8NoBom -Path $EnvPath -Content $content

    # CRITICO: Docker Compose prioriza las variables del proceso sobre el .env.
    # Si no actualizamos $env:WEBHOOK_URL, el contenedor queda con la URL vieja
    # (por ejemplo, http://localhost:5678/) aunque el .env ya tenga el tunel.
    $env:WEBHOOK_URL = $urlWithSlash
    [Environment]::SetEnvironmentVariable('WEBHOOK_URL', $urlWithSlash, 'Process')

    return $urlWithSlash
}

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Content
    )

    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}
