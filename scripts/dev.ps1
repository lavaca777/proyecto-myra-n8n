# =====================================================================
# Modo desarrollo completo (equivalente al antiguo start-all.ps1):
#   1. Levanta PostgreSQL + n8n y aplica migraciones.
#   2. Abre el tunel de Cloudflare.
#   3. Actualiza WEBHOOK_URL en .env y reinicia n8n.
#
# Uso: .\scripts\dev.ps1
# Ctrl+C cierra el tunel. Los contenedores siguen corriendo.
# =====================================================================

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\_env.ps1"

$root = Get-ProjectRoot
Set-Location $root

Assert-Docker

$existing = Get-Process cloudflared -ErrorAction SilentlyContinue
if ($existing) {
    Write-Warning 'Hay un proceso cloudflared corriendo. Si es de una sesion anterior, cierrala con Ctrl+C antes de continuar; si no, se creara otro tunel.'
}

Write-Host ''
Write-Host '=== 1/2  Stack + migraciones ===' -ForegroundColor Cyan
& (Join-Path $PSScriptRoot 'start.ps1')

Write-Host ''
Write-Host '=== 2/2  Tunel + webhook de Telegram ===' -ForegroundColor Cyan
& (Join-Path $PSScriptRoot 'tunnel.ps1')
