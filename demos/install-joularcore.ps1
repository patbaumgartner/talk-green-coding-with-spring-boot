#Requires -RunAsAdministrator
# Install JoularCore 0.0.1-beta-4 for Windows (x86_64)
# Installs joularcore.exe to C:\Program Files\joularcore\ and adds it to the system PATH

$VERSION    = "0.0.1-beta-4"
$ZIP_NAME   = "binaries-windows-x86_64.zip"
$DOWNLOAD_URL = "https://github.com/joular/joularcore/releases/download/$VERSION/$ZIP_NAME"
$INSTALL_DIR  = "C:\Program Files\joularcore"
$TMP_DIR      = Join-Path $env:TEMP ("joularcore_" + [System.IO.Path]::GetRandomFileName())

function Log { param([string]$msg) Write-Host ""; Write-Host "==> $msg" }

Log "Installing JoularCore $VERSION..."

# Create temp directory
New-Item -ItemType Directory -Path $TMP_DIR | Out-Null
$ZIP_PATH = Join-Path $TMP_DIR $ZIP_NAME

# Download
Log "Downloading $DOWNLOAD_URL..."
Invoke-WebRequest -Uri $DOWNLOAD_URL -OutFile $ZIP_PATH -UseBasicParsing

# Extract
Log "Extracting $ZIP_NAME..."
Expand-Archive -Path $ZIP_PATH -DestinationPath $TMP_DIR -Force

# Locate binary
$BINARY = Get-ChildItem -Path $TMP_DIR -Recurse -Filter "joularcore.exe" | Select-Object -First 1
if (-not $BINARY) {
    Write-Error "ERROR: joularcore.exe not found in zip contents:"
    Get-ChildItem -Path $TMP_DIR -Recurse | ForEach-Object { Write-Host $_.FullName }
    Remove-Item -Recurse -Force $TMP_DIR
    exit 1
}

# Install
Log "Installing to $INSTALL_DIR..."
if (-not (Test-Path $INSTALL_DIR)) {
    New-Item -ItemType Directory -Path $INSTALL_DIR | Out-Null
}
Copy-Item -Path $BINARY.FullName -Destination (Join-Path $INSTALL_DIR "joularcore.exe") -Force

# Add to system PATH if not already present
$currentPath = [System.Environment]::GetEnvironmentVariable("PATH", "Machine")
if ($currentPath -notlike "*$INSTALL_DIR*") {
    Log "Adding $INSTALL_DIR to system PATH..."
    [System.Environment]::SetEnvironmentVariable("PATH", "$currentPath;$INSTALL_DIR", "Machine")
    $env:PATH += ";$INSTALL_DIR"
    Write-Host "    PATH updated. Restart your shell to use 'joularcore' globally."
} else {
    Write-Host "    $INSTALL_DIR already in PATH."
}

Remove-Item -Recurse -Force $TMP_DIR

Log "joularcore installed: $INSTALL_DIR\joularcore.exe"
Write-Host "    Version: $((& "$INSTALL_DIR\joularcore.exe" --version 2>&1) -join ' ')" -ErrorAction SilentlyContinue

# Energy monitoring notes
Write-Host ""
Write-Host "=== Energy monitoring setup (required for power measurements) ==="
Write-Host ""
Write-Host "  JoularCore on Windows uses the Windows Energy Meter Interface (EMI)."
Write-Host "  This requires:"
Write-Host "    - A supported Intel CPU with RAPL counters"
Write-Host "    - Running joularcore.exe as Administrator"
Write-Host "    - Windows 10/11 with the Energy Meter Interface driver enabled"
Write-Host ""
Write-Host "  To start JoularCore (as Administrator):"
Write-Host "    joularcore.exe"
Write-Host ""
Write-Host "  See: https://github.com/joular/joularcore"
