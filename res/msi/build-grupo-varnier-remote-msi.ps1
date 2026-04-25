#Requires -Version 5.1
<#
.SYNOPSIS
  Gera o MSI do Gv Remote (WiX) para instalação e listagem em
  "Adicionar ou remover programas" (Apps e recursos).

.PREREQUISITES
  - Build Windows já gerado: flutter\build\windows\x64\runner\Release\
    (inclui Gv Remote.exe, data\, DLLs, etc.)
  - Python 3, NuGet, MSBuild (Visual Studio 2022 ou Build Tools) e WiX no PATH.
  - res\icon.ico (copiado para o ícone do instalador).

  Assinatura digital do MSI (opcional): Windows SDK (signtool.exe), certificado .pfx e:
    $env:HBB_CODESIGN_PFX = "C:\caminho\certificado.pfx"
    $env:HBB_CODESIGN_PFX_PASSWORD = "..."
  (Alternativa: CERT_PFX + P, como no build.py legado.)

.NOTES
  O preprocess.py altera ficheiros em res\msi (Includes.wxi, wxs, idiomas, etc.).
  Para repetir o build a partir do zero, faça git checkout dos ficheiros em res\msi
  ou clone limpo; o script apaga e recria a pasta de staging "rustdesk" na raiz do repo
  (já está no .gitignore).
#>
$ErrorActionPreference = "Stop"
$MsiRoot = $PSScriptRoot
$RepoRoot = (Resolve-Path (Join-Path $MsiRoot "..\..")).Path
$ReleaseDir = Join-Path $RepoRoot "flutter\build\windows\x64\runner\Release"
$StageDir = Join-Path $RepoRoot "rustdesk"
$Pubspec = Join-Path $RepoRoot "flutter\pubspec.yaml"

if (-not (Test-Path $ReleaseDir)) {
    Write-Error "Pasta de build não encontrada: $ReleaseDir`nExecute antes: flutter build windows --release (e copie librustdesk.dll se necessário)."
}

$exeName = "Gv Remote.exe"
$exePath = Join-Path $ReleaseDir $exeName
if (-not (Test-Path $exePath)) {
    Write-Error "Executável não encontrado: $exePath`nConfirme OUTPUT_NAME no CMake e refaça o build."
}

# version: 1.4.6+64 -> -v 1.4.6 --revision-version 64
$versionLine = Select-String -Path $Pubspec -Pattern '^\s*version:\s*([\d.]+)\+(\d+)\s*$' | Select-Object -First 1
if (-not $versionLine) {
    Write-Error "Não foi possível ler version de $Pubspec (esperado formato 1.2.3+45)."
}
$AppVersion = $versionLine.Matches[0].Groups[1].Value
$Revision = [int]$versionLine.Matches[0].Groups[2].Value

function Get-SignToolPathMsi {
    $cmd = Get-Command signtool.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $kitBin = Join-Path ${env:ProgramFiles(x86)} "Windows Kits\10\bin"
    if (Test-Path $kitBin) {
        return Get-ChildItem -Path $kitBin -Recurse -Filter signtool.exe -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match '\\x64\\' } |
            Sort-Object FullName -Descending |
            Select-Object -First 1 -ExpandProperty FullName
    }
    return $null
}

function Get-CodeSignPfxAndPassword {
    $pfx = $env:HBB_CODESIGN_PFX
    if (-not $pfx) { $pfx = $env:CERT_PFX }
    if (-not $pfx) {
        $devPfx = Join-Path $RepoRoot "res\codesign\gv-remote-dev-codesign.pfx"
        if (Test-Path -LiteralPath $devPfx) { $pfx = $devPfx }
    }
    if (-not $pfx) { return $null, $null }
    $pfx = (Resolve-Path -LiteralPath $pfx).Path
    $pw = $env:HBB_CODESIGN_PFX_PASSWORD
    if (-not $pw) { $pw = $env:P }
    if (-not $pw -and ($pfx -like "*gv-remote-dev-codesign*")) { $pw = "ChangeMe_DevOnly_123!" }
    if (-not $pw) { return $null, $null }
    return $pfx, $pw
}

function Sign-PeFilesInDirectory {
    param(
        [string] $Dir,
        [string] $PfxPath,
        [string] $PfxPassword,
        [string] $TimestampUrl
    )
    $st = Get-SignToolPathMsi
    if (-not $st) {
        Write-Warning "Assinatura dos binarios ignorada: signtool.exe nao encontrado (Windows SDK)."
        return
    }
    if (-not (Test-Path -LiteralPath $PfxPath)) { return }
    $files = @()
    $files += Get-ChildItem -Path $Dir -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in @(".exe", ".dll") }
    foreach ($f in $files) {
        Write-Host "A assinar:" $f.Name
        & $st sign /v /fd SHA256 /f $PfxPath /p $PfxPassword /tr $TimestampUrl /td SHA256 $f.FullName
        if ($LASTEXITCODE -ne 0) { throw "signtool falhou em $($f.Name) (código $LASTEXITCODE)" }
    }
    Write-Host "Binarios em $(Split-Path -Leaf $Dir) assinados: $($files.Count) ficheiro(s)."
}

$tsForAll = if ($env:HBB_CODESIGN_TIMESTAMP_URL) { $env:HBB_CODESIGN_TIMESTAMP_URL } else { "http://timestamp.digicert.com" }
$pfxRes, $pwRes = Get-CodeSignPfxAndPassword
if ($pfxRes -and $pwRes) {
    Write-Host "A assinar PEs em Release antes de empacotar no MSI..."
    Sign-PeFilesInDirectory -Dir $ReleaseDir -PfxPath $pfxRes -PfxPassword $pwRes -TimestampUrl $tsForAll
} else {
    Write-Warning "Binarios nao assinados (defina HBB_CODESIGN_PFX e HBB_CODESIGN_PFX_PASSWORD, ou coloque res\codesign\gv-remote-dev-codesign.pfx)."
}

Write-Host "Staging: $ReleaseDir -> $StageDir"
if (Test-Path $StageDir) {
    Remove-Item -Recurse -Force $StageDir
}
New-Item -ItemType Directory -Path $StageDir | Out-Null
Copy-Item -Path (Join-Path $ReleaseDir "*") -Destination $StageDir -Recurse -Force

Push-Location $MsiRoot
try {
    Write-Host "preprocess.py (--arp = entrada em Adicionar ou remover programas)..."
    $pyArgs = @(
        "preprocess.py",
        "--arp",
        "-d", "../../rustdesk",
        "--app-name", "Gv Remote",
        "-v", $AppVersion,
        "--revision-version", "$Revision",
        "-m", "Walter Junior"
    )
    & python @pyArgs
    if ($LASTEXITCODE -ne 0) { throw "preprocess.py falhou com código $LASTEXITCODE" }

    function Get-MsBuildExe {
        $candidates = @(
            (Get-Command msbuild -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source)
        ) | Where-Object { $_ }

        $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
        if (Test-Path $vswhere) {
            $fromVs = & $vswhere -latest -products * -requires Microsoft.Component.MSBuild `
                -find "MSBuild\**\Bin\MSBuild.exe" 2>$null | Select-Object -First 1
            if ($fromVs) { $candidates += $fromVs }
        }

        foreach ($p in $candidates) {
            if ($p -and (Test-Path $p)) { return $p }
        }
        return $null
    }

    $msbuild = Get-MsBuildExe
    if (-not $msbuild) {
        Write-Error "MSBuild não encontrado. Instale Visual Studio 2022 (carga de trabalho Desktop com C++) ou Build Tools, e o WiX Toolset v4."
    }
    Write-Host "MSBuild:" $msbuild

    Write-Host "Restaurar pacotes (NuGet / WiX)..."
    if (Get-Command nuget -ErrorAction SilentlyContinue) {
        & nuget restore msi.sln
        if ($LASTEXITCODE -ne 0) { throw "nuget restore falhou com código $LASTEXITCODE" }
    } else {
        # MSBuild restore works without .NET SDK; `dotnet restore` fails if only the host is installed.
        # RestorePackagesConfig=true pulls WixToolset.* for CustomActions.vcxproj (packages.config).
        & $msbuild msi.sln /t:Restore -p:Configuration=Release -p:Platform=x64 -p:RestorePackagesConfig=true
        if ($LASTEXITCODE -ne 0) { throw "msbuild /t:Restore falhou com código $LASTEXITCODE" }
    }

    Write-Host "Compilar MSI (Release x64)..."
    & $msbuild msi.sln -p:Configuration=Release -p:Platform=x64 /p:TargetVersion=Windows10
    if ($LASTEXITCODE -ne 0) { throw "msbuild falhou com código $LASTEXITCODE" }

    $msiCandidates = @(
        Join-Path $MsiRoot "Package\bin\x64\Release\en-us\Package.msi"
        Join-Path $MsiRoot "Package\bin\x64\Release\Package.msi"
    )
    $msi = $msiCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $msi) {
        $msi = (Get-ChildItem -Path $MsiRoot -Recurse -Filter "*.msi" -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName)
    }
    if ($msi) {
        Write-Host ""
        Write-Host "MSI gerado:" $msi

        # Assinatura digital (opcional): defina HBB_CODESIGN_PFX + HBB_CODESIGN_PFX_PASSWORD (ou CERT_PFX + P)
        $pfxPath = $env:HBB_CODESIGN_PFX
        if (-not $pfxPath) { $pfxPath = $env:CERT_PFX }
        $pfxPass = $env:HBB_CODESIGN_PFX_PASSWORD
        if (-not $pfxPass) { $pfxPass = $env:P }
        $tsUrl = $tsForAll

        $signExe = $null
        $cmd = Get-Command signtool.exe -ErrorAction SilentlyContinue
        if ($cmd) { $signExe = $cmd.Source }
        if (-not $signExe) {
            $kitBin = Join-Path ${env:ProgramFiles(x86)} "Windows Kits\10\bin"
            if (Test-Path $kitBin) {
                $signExe = Get-ChildItem -Path $kitBin -Recurse -Filter signtool.exe -ErrorAction SilentlyContinue |
                    Where-Object { $_.FullName -match '\\x64\\' } |
                    Sort-Object FullName -Descending |
                    Select-Object -First 1 -ExpandProperty FullName
            }
        }

        if ($pfxPath -and $pfxPass -and (Test-Path -LiteralPath $pfxPath) -and $signExe) {
            Write-Host "A assinar MSI com signtool..."
            & $signExe sign /v /fd SHA256 /f $pfxPath /p $pfxPass /tr $tsUrl /td SHA256 $msi
            if ($LASTEXITCODE -ne 0) { throw "signtool falhou ao assinar o MSI (código $LASTEXITCODE)" }
            Write-Host "MSI assinado."
        } elseif ($pfxPath -or $pfxPass) {
            Write-Warning "Assinatura MSI ignorada: defina PFX válido e palavra-passe, e instale Windows SDK (signtool)."
        }

        $gvMsiName = Join-Path (Split-Path -Parent $msi) "Gv Remote.msi"
        Copy-Item -LiteralPath $msi -Destination $gvMsiName -Force
        Write-Host "Gv Remote.msi:" $gvMsiName
    } else {
        Write-Warning "Build concluído mas nenhum .msi encontrado sob $MsiRoot."
    }
}
finally {
    Pop-Location
}
