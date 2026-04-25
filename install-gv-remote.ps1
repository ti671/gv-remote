#Requires -Version 5.1
<#
.SYNOPSIS
  Instala o Gv Remote e o GLPI Agent ja configurado para o servidor GLPI Inventory.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\install-gv-remote.ps1
#>
[CmdletBinding()]
param(
    [string] $GvRemoteRepo = "ti671/gv-remote",
    [string] $GvRemoteAssetPattern = "Gv*Remote*.msi",
    [string] $GlpiAgentRepo = "glpi-project/glpi-agent",
    [string] $GlpiAgentAssetPattern = "GLPI-Agent-*-x64.msi",
    [string] $GlpiServerUrl = "https://www.glpi.grupovarnier.app.br/plugins/glpiinventory",
    [string] $GvRemoteInstallArgs = "/qn /norestart",
    [string] $GlpiAgentInstallArgs = "/qn /norestart"
)

$ErrorActionPreference = "Stop"

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdministrator)) {
    $elevatedArgs = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", "`"$PSCommandPath`"",
        "-GvRemoteRepo", "`"$GvRemoteRepo`"",
        "-GvRemoteAssetPattern", "`"$GvRemoteAssetPattern`"",
        "-GlpiAgentRepo", "`"$GlpiAgentRepo`"",
        "-GlpiAgentAssetPattern", "`"$GlpiAgentAssetPattern`"",
        "-GlpiServerUrl", "`"$GlpiServerUrl`"",
        "-GvRemoteInstallArgs", "`"$GvRemoteInstallArgs`"",
        "-GlpiAgentInstallArgs", "`"$GlpiAgentInstallArgs`""
    )
    Start-Process -FilePath "powershell.exe" -ArgumentList $elevatedArgs -Verb RunAs -Wait
    exit $LASTEXITCODE
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Headers = @{
    "User-Agent" = "gv-remote-installer"
    "Accept" = "application/vnd.github+json"
}

function Get-LatestReleaseAsset {
    param(
        [Parameter(Mandatory = $true)][string] $Repo,
        [Parameter(Mandatory = $true)][string] $Pattern
    )

    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -Headers $Headers
    $asset = $release.assets | Where-Object { $_.name -like $Pattern } | Select-Object -First 1

    if (-not $asset) {
        throw "Nenhum asset encontrado na ultima release de $Repo com o padrao '$Pattern'."
    }

    return $asset
}

function Save-ReleaseAsset {
    param(
        [Parameter(Mandatory = $true)] $Asset,
        [Parameter(Mandatory = $true)][string] $DestinationDirectory
    )

    New-Item -ItemType Directory -Path $DestinationDirectory -Force | Out-Null
    $path = Join-Path $DestinationDirectory $Asset.name

    Write-Host "Baixando $($Asset.name)..."
    Invoke-WebRequest -Uri $Asset.browser_download_url -OutFile $path -Headers @{ "User-Agent" = "gv-remote-installer" }

    return $path
}

function Install-Msi {
    param(
        [Parameter(Mandatory = $true)][string] $Path,
        [Parameter(Mandatory = $true)][string] $Arguments
    )

    $msiArgs = "/i `"$Path`" $Arguments"
    $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $msiArgs -Wait -PassThru

    if ($process.ExitCode -ne 0) {
        throw "msiexec falhou para '$Path' com codigo $($process.ExitCode)."
    }
}

function Install-GvRemoteInventoryScript {
    $scriptDir = Join-Path $env:ProgramFiles "GLPI-Agent\scripts"
    New-Item -ItemType Directory -Path $scriptDir -Force | Out-Null

    $scriptPath = Join-Path $scriptDir "gvremote-id.bat"
    $scriptContent = @'
@echo off
setlocal

set "APP=C:\Program Files\Gv Remote\Gv Remote.exe"
set "MY_ID="

if exist "%APP%" (
  for /f "usebackq delims=" %%I in (`"%APP%" --get-id 2^>nul`) do (
    if not defined MY_ID set "MY_ID=%%I"
  )
)

echo { "remote_mgmt": [ { "type": "Gv Remote", "id": "%MY_ID%" } ] }
endlocal
'@

    Set-Content -LiteralPath $scriptPath -Value $scriptContent -Encoding ASCII
    Write-Host "Script de inventario criado: $scriptPath"
}

function Invoke-GlpiInventoryNow {
    $agentBat = Join-Path $env:ProgramFiles "GLPI-Agent\glpi-agent.bat"
    if (-not (Test-Path -LiteralPath $agentBat)) {
        Write-Warning "GLPI Agent instalado, mas glpi-agent.bat nao foi encontrado em: $agentBat"
        return
    }

    Write-Host "Executando inventario GLPI..."
    $process = Start-Process -FilePath $agentBat -ArgumentList "--tasks inventory --force" -Wait -PassThru
    if ($process.ExitCode -ne 0) {
        Write-Warning "Inventario GLPI retornou codigo $($process.ExitCode). Verifique o log do GLPI Agent."
    }
}

$tempDir = Join-Path $env:TEMP "gv-remote-install"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

$gvRemoteAsset = Get-LatestReleaseAsset -Repo $GvRemoteRepo -Pattern $GvRemoteAssetPattern
$gvRemoteMsi = Save-ReleaseAsset -Asset $gvRemoteAsset -DestinationDirectory $tempDir

Write-Host "Instalando Gv Remote..."
Install-Msi -Path $gvRemoteMsi -Arguments $GvRemoteInstallArgs
Write-Host "Gv Remote instalado com sucesso."

$glpiAgentAsset = Get-LatestReleaseAsset -Repo $GlpiAgentRepo -Pattern $GlpiAgentAssetPattern
$glpiAgentMsi = Save-ReleaseAsset -Asset $glpiAgentAsset -DestinationDirectory $tempDir

$glpiArgs = "$GlpiAgentInstallArgs SERVER=`"$GlpiServerUrl`" TASKS=`"inventory`" ADD_FIREWALL_EXCEPTION=1 RUNNOW=0"
Write-Host "Instalando GLPI Agent apontando para $GlpiServerUrl..."
Install-Msi -Path $glpiAgentMsi -Arguments $glpiArgs
Write-Host "GLPI Agent instalado com sucesso."

Install-GvRemoteInventoryScript
Invoke-GlpiInventoryNow

Write-Host "Implantacao concluida."
