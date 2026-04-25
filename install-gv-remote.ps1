#Requires -Version 5.1
<#
.SYNOPSIS
  Downloads and silently installs the latest Gv Remote MSI from GitHub Releases.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\install-gv-remote.ps1
#>
[CmdletBinding()]
param(
    [string] $Repo = "ti671/gv-remote",
    [string] $AssetNamePattern = "Gv*Remote*.msi",
    [string] $InstallArgs = "/qn /norestart"
)

$ErrorActionPreference = "Stop"

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdministrator)) {
    $argsList = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", "`"$PSCommandPath`"",
        "-Repo", "`"$Repo`"",
        "-AssetNamePattern", "`"$AssetNamePattern`"",
        "-InstallArgs", "`"$InstallArgs`""
    )
    Start-Process -FilePath "powershell.exe" -ArgumentList $argsList -Verb RunAs -Wait
    exit $LASTEXITCODE
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$headers = @{
    "User-Agent" = "gv-remote-installer"
    "Accept" = "application/vnd.github+json"
}

$release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -Headers $headers
$asset = $release.assets | Where-Object { $_.name -like $AssetNamePattern } | Select-Object -First 1

if (-not $asset) {
    throw "Nenhum asset MSI encontrado na ultima release de $Repo com o padrao '$AssetNamePattern'."
}

$tempDir = Join-Path $env:TEMP "gv-remote-install"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

$msiPath = Join-Path $tempDir $asset.name
Write-Host "Baixando $($asset.name)..."
Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $msiPath -Headers @{ "User-Agent" = "gv-remote-installer" }

Write-Host "Instalando Gv Remote..."
$process = Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$msiPath`" $InstallArgs" -Wait -PassThru
if ($process.ExitCode -ne 0) {
    throw "msiexec falhou com codigo $($process.ExitCode)."
}

Write-Host "Gv Remote instalado com sucesso."
