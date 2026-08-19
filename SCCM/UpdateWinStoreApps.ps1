# === Run this as a "Run PowerShell Script" step ===
# Do NOT check "Run this step as the following account" — leave it as SYSTEM

# Find the latest DesktopAppInstaller folder
$AppInstallerPath = Get-ChildItem "C:\Program Files\WindowsApps\" -Filter "Microsoft.DesktopAppInstaller*_x64__8wekyb3d8bbwe" -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending |
    Select-Object -First 1

if (-not $AppInstallerPath) {
    Write-Error "Microsoft.DesktopAppInstaller package not found. Ensure App Installer is installed/provisioned on the image."
    exit 1
}

$wingetExe = Join-Path $AppInstallerPath.FullName "winget.exe"

Write-Host "Using winget at: $wingetExe"

# Change into the folder (critical for permissions)
Set-Location $AppInstallerPath.FullName

Write-Host "Adding Exclusions..."
& .\winget.exe pin add --id "Greenshot.Greenshot" --accept-source-agreements
& .\winget.exe pin add --id "Microsoft.Office"
& .\winget.exe pin add --id "Microsoft.PowerBI"

Write-Host "Resetting sources..."
& .\winget.exe source reset --force

Write-Host "Updating sources..."
& .\winget.exe source update

# Continue if winget failure in updating.
$ErrorActionPreference = 'Continue'

Write-Host "Upgrading..."
& .\winget.exe upgrade --all --scope machine --silent --accept-package-agreements --accept-source-agreements --disable-interactivity --force

# Optional: Install a specific app
#ECHO "Updating individual apps..."
# & .\winget.exe install --id "Google.Chrome" --exact --scope machine --silent --accept-package-agreements --accept-source-agreements
# & .\winget upgrade --name "Microsoft Photos" --scope machine --silent --accept-package-agreements --accept-source-agreements

Stop-Transcript
