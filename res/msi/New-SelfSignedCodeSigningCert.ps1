#Requires -Version 5.1
<#
.SYNOPSIS
  Cria um certificado de assinatura de código (Authenticode) autoassinado e exporta um .pfx.

.DESCRIPTION
  Serve para testar signtool / build assinado localmente. Em outros PCs o Windows mostrará
  "Editor desconhecido" ou aviso de SmartScreen até o .cer ser instalado em "Autores de confiança".

.PARAMETER Subject
  Nome distinto do certificado (predefinido: Gv Remote desenvolvimento).

.PARAMETER OutPfx
  Caminho do ficheiro .pfx a criar (predefinido: res/codesign/gv-remote-dev-codesign.pfx na raiz do repo).

.PARAMETER Password
  Palavra-passe do PFX (predefinida só para dev — altere em produção).

.PARAMETER ValidYears
  Validade em anos (predefinido: 5).

.PARAMETER TrustCurrentUser
  Se definido, importa o .cer em Autores de confiança do utilizador atual (reduz avisos nesta máquina).

.EXAMPLE
  .\New-SelfSignedCodeSigningCert.ps1
  $env:HBB_CODESIGN_PFX = (Resolve-Path .\res\codesign\gv-remote-dev-codesign.pfx)
  $env:HBB_CODESIGN_PFX_PASSWORD = 'ChangeMe_DevOnly_123!'
#>
[CmdletBinding()]
param(
    [string] $Subject = "CN=Gv Remote (desenvolvimento autoassinado)",
    [string] $OutPfx = "",
    [string] $Password = "ChangeMe_DevOnly_123!",
    [int] $ValidYears = 5,
    [switch] $TrustCurrentUser
)

$ErrorActionPreference = "Stop"
$MsiRoot = $PSScriptRoot
$RepoRoot = (Resolve-Path (Join-Path $MsiRoot "..\..")).Path
$CodesignDir = Join-Path $RepoRoot "res\codesign"
if (-not $OutPfx) {
    $OutPfx = Join-Path $CodesignDir "gv-remote-dev-codesign.pfx"
}
$OutPfx = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutPfx)
$OutCer = [System.IO.Path]::ChangeExtension($OutPfx, "cer")

if (-not (Test-Path $CodesignDir)) {
    New-Item -ItemType Directory -Path $CodesignDir | Out-Null
}

Write-Host "A criar certificado autoassinado (Code Signing)..."
$cert = New-SelfSignedCertificate `
    -Subject $Subject `
    -Type CodeSigningCert `
    -KeySpec Signature `
    -KeyExportPolicy Exportable `
    -KeyLength 2048 `
    -HashAlgorithm SHA256 `
    -NotAfter (Get-Date).AddYears($ValidYears) `
    -CertStoreLocation "Cert:\CurrentUser\My"

try {
    $sec = ConvertTo-SecureString -String $Password -AsPlainText -Force
    Export-PfxCertificate -Cert $cert -FilePath $OutPfx -Password $sec | Out-Null
    Export-Certificate -Cert $cert -FilePath $OutCer -Type CERT | Out-Null
}
finally {
    Remove-Item -Path "Cert:\CurrentUser\My\$($cert.Thumbprint)" -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "PFX criado: $OutPfx"
Write-Host "CER exportado: $OutCer"
Write-Host ""
Write-Host "Para assinar builds (PowerShell):"
Write-Host ('  $env:HBB_CODESIGN_PFX="{0}"' -f $OutPfx)
Write-Host ('  $env:HBB_CODESIGN_PFX_PASSWORD="{0}"' -f $Password)
Write-Host "  python build.py --flutter --skip-portable-pack"
Write-Host "  .\build-grupo-varnier-remote-msi.ps1"
Write-Host ""
Write-Host "Nota: autoassinado = nao confiavel globalmente. Outros PCs veem aviso ate instalarem o .cer."

if ($TrustCurrentUser) {
    Write-Host "A importar para Autores de confianca (utilizador atual)..."
    Import-Certificate -FilePath $OutCer -CertStoreLocation "Cert:\CurrentUser\TrustedPublisher" | Out-Null
    Write-Host "Importacao concluida."
}
