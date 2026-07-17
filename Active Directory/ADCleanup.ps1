<#
.SYNOPSIS
    Optimized Active Directory Stale Objects Cleanup Script
    Action Modes:
      - "Report"            → Reporting only (no changes)
      - "Disable"           → Disable stale objects (after DisableAfterDays)
      - "DisableAndDelete"  → Disable + Delete (Delete happens after DeleteAfterDays)
#>

# ========================== CONFIGURATION VARIABLES ==========================

$DisableAfterDays = 180
$DeleteAfterDays  = 365

$Action = "Report"          # Options: "Report", "Disable", "DisableAndDelete"

$LogPath = "D:\Logs\"

# === IGNORE GROUPS ===
$IgnoreUserGroups     = @("Domain Admins", "Enterprise Admins", "Schema Admins")
$IgnoreComputerGroups = @()  

# === IGNORE OUs ===
$IgnoreOUs = @(
    #"OU=Protected Users,DC=contoso,DC=com"
)

# ============================================================================

if (-not (Test-Path $LogPath)) {
    New-Item -Path $LogPath -ItemType Directory -Force | Out-Null
}

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"

# Output files
$ReportUsersFile     = Join-Path $LogPath "Stale_Report_Users_${timestamp}.csv"
$ReportCompsFile     = Join-Path $LogPath "Stale_Report_Computers_${timestamp}.csv"
$DisabledUsersFile   = Join-Path $LogPath "Disabled_Users_${timestamp}.csv"
$DisabledCompsFile   = Join-Path $LogPath "Disabled_Computers_${timestamp}.csv"
$DeletedUsersFile    = Join-Path $LogPath "Deleted_Users_${timestamp}.csv"
$DeletedCompsFile    = Join-Path $LogPath "Deleted_Computers_${timestamp}.csv"
$WarningUsersFile    = Join-Path $LogPath "HalfTime_Inactive_Users_${timestamp}.csv"
$WarningCompsFile    = Join-Path $LogPath "HalfTime_Inactive_Computers_${timestamp}.csv"
$IgnoredFile         = Join-Path $LogPath "Ignored_Protected_Objects_${timestamp}.csv"

# Calculate dates
$DisableDate = (Get-Date).AddDays(-$DisableAfterDays)
$DeleteDate  = (Get-Date).AddDays(-$DeleteAfterDays)
$WarningDate = (Get-Date).AddDays(-[math]::Round($DisableAfterDays / 2))

Write-Host "=== Active Directory Stale Objects Script ===" -ForegroundColor Cyan
Write-Host "Disable after      : $DisableAfterDays days"
Write-Host "Delete after       : $DeleteAfterDays days"
Write-Host "Half-time warning  : $([math]::Round($DisableAfterDays / 2)) days"
Write-Host "Action Mode        : $Action"
Write-Host "Log Path           : $LogPath`n"

Import-Module ActiveDirectory -ErrorAction Stop

# ====================== HELPER FUNCTIONS ======================
function Get-LastActivityDate {
    param($ADObject)
    $dates = @()
    if ($ADObject.LastLogonTimestamp -gt 0) { try { $dates += [DateTime]::FromFileTime($ADObject.LastLogonTimestamp) } catch {} }
    if ($ADObject.PasswordLastSet)      { $dates += $ADObject.PasswordLastSet }
    if ($ADObject.WhenChanged)          { $dates += $ADObject.WhenChanged }
    if ($ADObject.WhenCreated)          { $dates += $ADObject.WhenCreated }
    if ($ADObject.LastBadPasswordAttempt -gt 0) { try { $dates += [DateTime]::FromFileTime($ADObject.LastBadPasswordAttempt) } catch {} }
    if ($dates.Count -gt 0) { return ($dates | Sort-Object -Descending)[0] }
    return $null
}

function Test-IsInIgnoreOU {
    param([string]$DN, [string[]]$OUs)
    foreach ($ou in $OUs) { if ($DN -like "*,$ou") { return $true } }
    return $false
}

# ====================== PROCESS USERS ======================
Write-Host "Analyzing enabled Users..." -ForegroundColor Yellow -NoNewline
$Users = Get-ADUser -Filter {Enabled -eq $true} -Properties Name,SamAccountName,UserPrincipalName,DistinguishedName,LastLogonTimestamp,PasswordLastSet,WhenChanged,WhenCreated,Description,LastBadPasswordAttempt,MemberOf -ResultPageSize 2000

$ToDisableUsers = @(); $ToDeleteUsers = @(); $WarningUsers = @()
$IgnoredObjects = @()
$counter = 0

foreach ($user in $Users) {
    $counter++
    if ($counter % 300 -eq 0) { Write-Host "." -NoNewline }

    if (Test-IsInIgnoreOU -DN $user.DistinguishedName -OUs $IgnoreOUs) {
        $IgnoredObjects += [PSCustomObject]@{ObjectType='User'; Name=$user.Name; SamAccountName=$user.SamAccountName; Reason="In protected OU"}
        continue
    }

    $isProtected = $false
    if ($IgnoreUserGroups.Count -gt 0) {
        foreach ($group in $IgnoreUserGroups) {
            if ($user.MemberOf -like "*CN=$group,*") { $isProtected = $true; break }
        }
    }
    if ($isProtected) {
        $IgnoredObjects += [PSCustomObject]@{ObjectType='User'; Name=$user.Name; SamAccountName=$user.SamAccountName; Reason="Member of protected group"}
        continue
    }

    $lastActivity = Get-LastActivityDate $user
    if (-not $lastActivity) { continue }

    $daysInactive = ((Get-Date) - $lastActivity).Days
    $obj = [PSCustomObject]@{
        Name = $user.Name; SamAccountName = $user.SamAccountName; UserPrincipalName = $user.UserPrincipalName
        DistinguishedName = $user.DistinguishedName; LastActivityDate = $lastActivity; DaysInactive = $daysInactive
        Description = $user.Description
    }

    if ($lastActivity -lt $DeleteDate)      { $ToDeleteUsers += $obj }
    elseif ($lastActivity -lt $DisableDate) { $ToDisableUsers += $obj }
    elseif ($lastActivity -lt $WarningDate) { $WarningUsers += $obj }
}
Write-Host " Done ($($Users.Count) users)" -ForegroundColor Green

# ====================== PROCESS COMPUTERS ======================
Write-Host "Analyzing enabled Computers..." -ForegroundColor Yellow -NoNewline
$Computers = Get-ADComputer -Filter {Enabled -eq $true} -Properties Name,SamAccountName,DistinguishedName,LastLogonTimestamp,PasswordLastSet,WhenChanged,WhenCreated,Description,OperatingSystem,LastBadPasswordAttempt,MemberOf -ResultPageSize 2000

$ToDisableComps = @(); $ToDeleteComps = @(); $WarningComps = @()
$counter = 0

foreach ($comp in $Computers) {
    $counter++
    if ($counter % 100 -eq 0) { Write-Host "." -NoNewline }

    if (Test-IsInIgnoreOU -DN $comp.DistinguishedName -OUs $IgnoreOUs) {
        $IgnoredObjects += [PSCustomObject]@{ObjectType='Computer'; Name=$comp.Name; SamAccountName=$comp.SamAccountName; Reason="In protected OU"}
        continue
    }

    $isProtected = $false
    if ($IgnoreComputerGroups.Count -gt 0) {
        foreach ($group in $IgnoreComputerGroups) {
            if ($comp.MemberOf -like "*CN=$group,*") { $isProtected = $true; break }
        }
    }
    if ($isProtected) {
        $IgnoredObjects += [PSCustomObject]@{ObjectType='Computer'; Name=$comp.Name; SamAccountName=$comp.SamAccountName; Reason="Member of protected group"}
        continue
    }

    $lastActivity = Get-LastActivityDate $comp
    if (-not $lastActivity) { continue }

    $daysInactive = ((Get-Date) - $lastActivity).Days
    $obj = [PSCustomObject]@{
        Name = $comp.Name; SamAccountName = $comp.SamAccountName; DistinguishedName = $comp.DistinguishedName
        LastActivityDate = $lastActivity; DaysInactive = $daysInactive; OperatingSystem = $comp.OperatingSystem
        Description = $comp.Description
    }

    if ($lastActivity -lt $DeleteDate)      { $ToDeleteComps += $obj }
    elseif ($lastActivity -lt $DisableDate) { $ToDisableComps += $obj }
    elseif ($lastActivity -lt $WarningDate) { $WarningComps += $obj }
}
Write-Host " Done ($($Computers.Count) computers)" -ForegroundColor Green

# ====================== EXECUTE ACTIONS ======================
if ($Action -ne "Report") {
    Write-Host "`nPerforming actions ($Action mode)..." -ForegroundColor Magenta

    # Disable objects (used in both "Disable" and "DisableAndDelete")
    foreach ($item in $ToDisableUsers) {
        try { 
            Disable-ADAccount -Identity $item.DistinguishedName -Confirm:$false
            $item | Add-Member -NotePropertyName ActionTaken -NotePropertyValue 'DISABLED' -Force
        } catch { Write-Warning "Failed to disable user $($item.Name): $_" }
    }
    foreach ($item in $ToDisableComps) {
        try { 
            Set-ADComputer -Identity $item.DistinguishedName -Enabled $false -Confirm:$false
            $item | Add-Member -NotePropertyName ActionTaken -NotePropertyValue 'DISABLED' -Force
        } catch { Write-Warning "Failed to disable computer $($item.Name): $_" }
    }

    # Delete objects (only in "DisableAndDelete" mode)
    if ($Action -eq "DisableAndDelete") {
        foreach ($item in $ToDeleteUsers) {
            try { 
                Remove-ADUser -Identity $item.DistinguishedName -Confirm:$false
                $item | Add-Member -NotePropertyName ActionTaken -NotePropertyValue 'DELETED' -Force
            } catch { Write-Warning "Failed to delete user $($item.Name): $_" }
        }
        foreach ($item in $ToDeleteComps) {
            try { 
                Remove-ADComputer -Identity $item.DistinguishedName -Confirm:$false
                $item | Add-Member -NotePropertyName ActionTaken -NotePropertyValue 'DELETED' -Force
            } catch { Write-Warning "Failed to delete computer $($item.Name): $_" }
        }
    }
} else {
    # Report mode
    $ToDisableUsers | ForEach-Object { $_ | Add-Member ActionTaken 'WOULD BE DISABLED' -Force }
    $ToDeleteUsers  | ForEach-Object { $_ | Add-Member ActionTaken 'WOULD BE DELETED' -Force }
    $ToDisableComps | ForEach-Object { $_ | Add-Member ActionTaken 'WOULD BE DISABLED' -Force }
    $ToDeleteComps  | ForEach-Object { $_ | Add-Member ActionTaken 'WOULD BE DELETED' -Force }
}

# ====================== EXPORT TO CSV ======================
$csvParams = @{ NoTypeInformation = $true; Encoding = 'UTF8' }

# Users
if ($ToDisableUsers.Count + $ToDeleteUsers.Count -gt 0) { ($ToDisableUsers + $ToDeleteUsers) | Export-Csv $ReportUsersFile @csvParams }
if ($ToDisableUsers.Count -gt 0) { $ToDisableUsers | Export-Csv $DisabledUsersFile @csvParams }
if ($ToDeleteUsers.Count -gt 0 -and $Action -eq "DisableAndDelete") { $ToDeleteUsers | Export-Csv $DeletedUsersFile @csvParams }

if ($WarningUsers.Count -gt 0) {
    $WarningUsers | Export-Csv $WarningUsersFile @csvParams
    Write-Host "Half-time Inactive Users → $WarningUsersFile" -ForegroundColor Cyan
}

# Computers
if ($ToDisableComps.Count + $ToDeleteComps.Count -gt 0) { ($ToDisableComps + $ToDeleteComps) | Export-Csv $ReportCompsFile @csvParams }
if ($ToDisableComps.Count -gt 0) { $ToDisableComps | Export-Csv $DisabledCompsFile @csvParams }
if ($ToDeleteComps.Count -gt 0 -and $Action -eq "DisableAndDelete") { $ToDeleteComps | Export-Csv $DeletedCompsFile @csvParams }

if ($WarningComps.Count -gt 0) {
    $WarningComps | Export-Csv $WarningCompsFile @csvParams
    Write-Host "Half-time Inactive Computers → $WarningCompsFile" -ForegroundColor Cyan
}

if ($IgnoredObjects.Count -gt 0) {
    $IgnoredObjects | Export-Csv $IgnoredFile @csvParams
    Write-Host "Ignored/Protected Objects → $IgnoredFile" -ForegroundColor Magenta
}

Write-Host "`nScript completed successfully!" -ForegroundColor Cyan
