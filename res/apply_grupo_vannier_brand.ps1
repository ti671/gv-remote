# Gera tamanhos de icone a partir de um PNG fonte (Grupo Vannier).
# Requer: Windows PowerShell 5+ com GDI+ (System.Drawing).
param(
  [string]$Source = ""
)

$ErrorActionPreference = "Stop"
if (-not $Source) {
  $candidates = @(
    "C:\Users\GV TI\.cursor\projects\c-Users-GV-TI-Documents-GitHub-rustdesk\assets\c__Users_GV_TI_AppData_Roaming_Cursor_User_workspaceStorage_1b69890132a28287b0587e1a2fd24f35_images_logo-GLPI-250-black-1f75c1d3-e386-4dc6-bda3-171923285b8c.png"
  )
  foreach ($c in $candidates) { if (Test-Path $c) { $Source = $c; break } }
}
if (-not (Test-Path $Source)) { throw "Ficheiro fonte nao encontrado: defina -Source" }

Add-Type -AssemblyName System.Drawing

function Save-ResizedPng {
  param([string]$InPath, [int]$W, [int]$H, [string]$OutPath)
  $src = [System.Drawing.Image]::FromFile($InPath)
  try {
    $bmp = New-Object System.Drawing.Bitmap([int]$W, [int]$H, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.Clear([System.Drawing.Color]::FromArgb(0, 0, 0, 0))
    $g.DrawImage($src, 0, 0, $W, $H)
    $g.Dispose()
    $dir = Split-Path $OutPath -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $bmp.Save($OutPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
  } finally { $src.Dispose() }
}

function Save-IconFromImage {
  param([string]$InPath, [int]$Size, [string]$OutIco)
  $src = [System.Drawing.Image]::FromFile($InPath)
  try {
    $bmp = New-Object System.Drawing.Bitmap([int]$Size, [int]$Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.DrawImage($src, 0, 0, $Size, $Size)
    $g.Dispose()
    $hIcon = $bmp.GetHicon()
    $icon = [System.Drawing.Icon]::FromHandle($hIcon)
    $fs = [System.IO.File]::Create($OutIco)
    try { $icon.Save($fs) } finally { $fs.Close(); $icon.Dispose(); $bmp.Dispose() }
  } finally { $src.Dispose() }
}

$repo = Resolve-Path (Join-Path $PSScriptRoot "..") | ForEach-Object { $_.Path }
$res = Join-Path $repo "res"
$flutter = Join-Path $repo "flutter"
$assets = Join-Path $flutter "assets"
if (-not (Test-Path $assets)) { New-Item -ItemType Directory -Path $assets -Force | Out-Null }

# res/ (Rust/Windows)
Save-ResizedPng -InPath $Source -W 32 -H 32 -OutPath (Join-Path $res "32x32.png")
Save-ResizedPng -InPath $Source -W 64 -H 64 -OutPath (Join-Path $res "64x64.png")
Save-ResizedPng -InPath $Source -W 128 -H 128 -OutPath (Join-Path $res "128x128.png")
Save-ResizedPng -InPath $Source -W 256 -H 256 -OutPath (Join-Path $res "128x128@2x.png")
Copy-Item -Force $Source (Join-Path $res "icon.png")
Copy-Item -Force $Source (Join-Path $res "mac-icon.png")
# tray mac
Save-ResizedPng -InPath $Source -W 44 -H 44 -OutPath (Join-Path $res "mac-tray-light-x2.png")
Save-ResizedPng -InPath $Source -W 44 -H 44 -OutPath (Join-Path $res "mac-tray-dark-x2.png")

Save-IconFromImage -InPath $Source -Size 256 -OutIco (Join-Path $res "icon.ico")
Save-IconFromImage -InPath $Source -Size 32 -OutIco (Join-Path $res "tray-icon.ico")

# Flutter in-app
Copy-Item -Force $Source (Join-Path $assets "logo.png")
Save-IconFromImage -InPath $Source -Size 256 -OutIco (Join-Path $assets "icon.ico")

# Windows Flutter runner
$winIcon = Join-Path $flutter "windows\runner\resources\app_icon.ico"
if (Test-Path (Split-Path $winIcon -Parent)) {
  Save-IconFromImage -InPath $Source -Size 256 -OutIco $winIcon
}

# Android mipmaps
$androidRes = Join-Path $flutter "android\app\src\main\res"
$sizes = @{
  "mipmap-mdpi"         = 48
  "mipmap-hdpi"         = 72
  "mipmap-xhdpi"        = 96
  "mipmap-xxhdpi"       = 144
  "mipmap-xxxhdpi"      = 192
}
foreach ($e in $sizes.GetEnumerator()) {
  $folder = Join-Path $androidRes $e.Key
  if (-not (Test-Path $folder)) { continue }
  $s = $e.Value
  foreach ($n in @("ic_launcher.png", "ic_launcher_foreground.png", "ic_launcher_round.png")) {
    Save-ResizedPng -InPath $Source -W $s -H $s -OutPath (Join-Path $folder $n)
  }
  Save-ResizedPng -InPath $Source -W 24 -H 24 -OutPath (Join-Path $folder "ic_stat_logo.png")
}

Write-Host "Branding Grupo Vannier aplicado a partir de: $Source"
