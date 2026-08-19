# ================================================
# Install the absolute latest winget from GitHub
# ================================================

$progressPreference = 'silentlyContinue'

Write-Host "Checking GitHub for the latest winget release..." -ForegroundColor Yellow

try {
    # Get latest release info (with retry for reliability)
    $latestRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/microsoft/winget-cli/releases/latest" -ErrorAction Stop
    
    $tag = $latestRelease.tag_name
    $version = $tag.TrimStart('v')
    
    # Find the msixbundle asset
    $msixAsset = $latestRelease.assets | Where-Object { $_.name -like "*.msixbundle" } | Select-Object -First 1
    
    if (-not $msixAsset) {
        Write-Host "❌ No .msixbundle found in the latest release ($tag). Trying pre-releases..." -ForegroundColor Red
        
        # Fallback: Get the most recent pre-release if needed
        $releases = Invoke-RestMethod -Uri "https://api.github.com/repos/microsoft/winget-cli/releases" -ErrorAction Stop
        $latestRelease = $releases | Where-Object { $_.assets | Where-Object { $_.name -like "*.msixbundle" } } | Select-Object -First 1
        $tag = $latestRelease.tag_name
        $version = $tag.TrimStart('v')
        $msixAsset = $latestRelease.assets | Where-Object { $_.name -like "*.msixbundle" } | Select-Object -First 1
    }

    if (-not $msixAsset) {
        Write-Host "❌ Could not find any msixbundle asset. Please check manually on GitHub." -ForegroundColor Red
        return
    }

    $downloadUrl = $msixAsset.browser_download_url

    Write-Host "Latest version found: $version ($tag)" -ForegroundColor Cyan
    Write-Host "Downloading winget v$version..." -ForegroundColor Yellow

    $tempFile = "$env:TEMP\Microsoft.DesktopAppInstaller_$version.msixbundle"
    Invoke-WebRequest -Uri $downloadUrl -OutFile $tempFile -ErrorAction Stop

    # Install
    Add-AppxPackage -Path $tempFile -ForceApplicationShutdown

    # Cleanup
    Remove-Item $tempFile -ErrorAction SilentlyContinue

    Write-Host "✅ winget successfully updated to version $version!" -ForegroundColor Green
    Write-Host "Close ALL PowerShell windows and reopen a new one, then run:" -ForegroundColor Cyan
    Write-Host "   winget --version" -ForegroundColor White

} catch {
    Write-Host "❌ Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Tip: Try running this again, or download manually from https://github.com/microsoft/winget-cli/releases" -ForegroundColor Yellow
}
