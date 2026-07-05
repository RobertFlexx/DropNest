param(
  [switch]$Uninstall,
  [switch]$Help
)

$Owner = if ($env:GITHUB_OWNER) { $env:GITHUB_OWNER } else { "RobertFlexx" }
$Repo = if ($env:GITHUB_REPO) { $env:GITHUB_REPO } else { "dropnest" }
$BinaryName = "dropnest"
$InstallDir = if ($env:INSTALL_DIR) { $env:INSTALL_DIR } else { Join-Path $env:USERPROFILE ".local\bin" }
$ShipmentPath = Join-Path $InstallDir "dropnest-shipment"
$WrapperPath = Join-Path $InstallDir "dropnest.cmd"
$BaseUrl = "https://github.com/$Owner/$Repo/releases/latest/download"
$ArchiveName = "dropnest-windows.zip"
$ChecksumName = "dropnest-windows.zip.sha256"

function Show-Help {
  Write-Host "DropNest installer"
  Write-Host ""
  Write-Host "Usage:"
  Write-Host "  powershell -ExecutionPolicy Bypass -File install.ps1"
  Write-Host "  powershell -ExecutionPolicy Bypass -File install.ps1 -Uninstall"
  Write-Host ""
  Write-Host "DropNest is distributed as a Gleam Erlang shipment. It requires Erlang to run."
  Write-Host "Set GITHUB_OWNER or GITHUB_REPO to install from a fork."
}

if ($Help) {
  Show-Help
  exit 0
}

if ($Uninstall) {
  Remove-Item -Force -ErrorAction SilentlyContinue $WrapperPath
  Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $ShipmentPath
  Write-Host "DropNest removed from $InstallDir"
  exit 0
}

if (-not (Get-Command erl -ErrorAction SilentlyContinue)) {
  Write-Host "Erlang was not found." -ForegroundColor Red
  Write-Host ""
  Write-Host "DropNest is a Gleam/BEAM application, so it needs Erlang installed."
  Write-Host "Install Erlang from https://www.erlang.org/downloads or with a package manager, then run this installer again."
  exit 1
}

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

$TempDir = New-Item -ItemType Directory -Force -Path (Join-Path ([System.IO.Path]::GetTempPath()) ("dropnest-install-" + [System.Guid]::NewGuid()))
$Archive = Join-Path $TempDir $ArchiveName
$Checksum = Join-Path $TempDir $ChecksumName
$ExtractDir = Join-Path $TempDir "extract"

try {
  Write-Host "Downloading DropNest from GitHub Releases..."
  Invoke-WebRequest -Uri "$BaseUrl/$ArchiveName" -OutFile $Archive

  try {
    Invoke-WebRequest -Uri "$BaseUrl/$ChecksumName" -OutFile $Checksum
    $Expected = (Get-Content $Checksum | Select-Object -First 1).Split(" ")[0].ToLowerInvariant()
    $Actual = (Get-FileHash -Algorithm SHA256 $Archive).Hash.ToLowerInvariant()
    if ($Expected -ne $Actual) {
      throw "Checksum verification failed."
    }
  } catch {
    Write-Host "Checksum verification was not completed: $_"
  }

  Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $ShipmentPath
  New-Item -ItemType Directory -Force -Path $ExtractDir | Out-Null
  Expand-Archive -Force -Path $Archive -DestinationPath $ExtractDir
  Move-Item -Force (Join-Path $ExtractDir "erlang-shipment") $ShipmentPath

  $Entrypoint = Join-Path $ShipmentPath "entrypoint.ps1"
  Set-Content -Path $WrapperPath -Encoding ASCII -Value "@echo off`r`npowershell -ExecutionPolicy Bypass -File `"$Entrypoint`" run %*`r`n"

  Write-Host ""
  Write-Host "DropNest installed."
  Write-Host ""
  Write-Host "Run:"
  Write-Host "  dropnest serve"
  Write-Host ""
  Write-Host "LAN mode:"
  Write-Host "  dropnest serve --lan --pin 1234 --dir `"$env:USERPROFILE\Downloads\DropNest`""

  $PathParts = $env:PATH -split ";"
  if ($PathParts -notcontains $InstallDir) {
    Write-Host ""
    Write-Host "Warning: $InstallDir is not in PATH."
    Write-Host "Add it to your user PATH if 'dropnest' is not found."
  }
} finally {
  Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $TempDir
}
