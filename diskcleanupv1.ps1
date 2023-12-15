param(
    [uint32]$Age = $env:profileage,
    [bool]$ReadOnlyMode
)

# Determine the value of $ReadOnlyMode based on the environment variable
try {
    $ReadOnlyMode = [System.Convert]::ToBoolean($env:readonly)
} catch {
    $ReadOnlyMode = $true
}

# Function to get Disk Space
function Get-DiskSpace {
    $drive = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -eq "C:\" }
    [PSCustomObject]@{
        TotalSizeGB = [math]::Round(($drive.Used + $drive.Free) / 1GB, 2)
        UsedSpaceGB = [math]::Round($drive.Used / 1GB, 2)
        FreeSpaceGB = [math]::Round($drive.Free / 1GB, 2)
    }
}

# Function to safely delete a user profile
function Remove-UserProfile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProfilePath
    )

    try {
        Remove-Item -Path $ProfilePath -Recurse -Force
        Write-Host "Successfully deleted profile at: $ProfilePath"
    } catch {
        Write-Host "Error deleting profile at: $ProfilePath. Error: $_"
    }
}

# Function to convert SID to username
function Convert-SIDToUsername {
    param (
        [string]$SID
    )
    try {
        $objSID = New-Object System.Security.Principal.SecurityIdentifier($SID)
        $objUser = $objSID.Translate([System.Security.Principal.NTAccount])
        return $objUser.Value
    } catch {
        return $null
    }
}

# Function to get profile size
function Get-ProfileSize {
    param (
        [string]$ProfilePath
    )
    try {
        $size = (Get-ChildItem -Path $ProfilePath -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        return [math]::Round($size / 1GB, 2) # Convert to GB
    } catch {
        return $null
    }
}

# Welcome the user
Write-Host "`nHello friend! Welcome to Ben's disk cleanup script :)`n"

# Notify if running in read-only mode
if ($ReadOnlyMode) {
    Write-Host "RUNNING IN READ ONLY MODE - No changes will be made to the system"
}

$ProfilePath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList"
$ComputerProfiles = Get-ChildItem "$ProfilePath"
$CurrentDate = Get-Date
$RemovedRegistryEntries = @()
$OrphanedProfileFound = $false

# Get the profile path for logged-on users
$LoggedOnUserPaths = Get-CimInstance Win32_Process -Filter "name like 'explorer.exe'" | 
    ForEach-Object {
        $owner = $_ | Invoke-CimMethod -MethodName GetOwner -ErrorAction SilentlyContinue
        if ($owner) {
            (Get-WmiObject -Class Win32_UserProfile | Where-Object { $_.SID -eq (New-Object System.Security.Principal.NTAccount($owner.Domain, $owner.User)).Translate([System.Security.Principal.SecurityIdentifier]).Value }).LocalPath
        }
    } | Where-Object { $_ } | Select-Object -Unique

$InitialDiskSpace = Get-DiskSpace
Write-Host "Initial Disk Space: Total: $($InitialDiskSpace.TotalSizeGB) GB, Used: $($InitialDiskSpace.UsedSpaceGB) GB, Free: $($InitialDiskSpace.FreeSpaceGB) GB"
    
# Start of profile analysis
Write-Host "Scanning for Profiles...`n"

# List all non-system profiles
Write-Host "Profiles Found:"
$ComputerProfiles | ForEach-Object {
    $profileInfo = Get-ItemProperty "$ProfilePath\$($_.PSChildName)"
    $ProfileName = [System.IO.Path]::GetFileName($profileInfo.ProfileImagePath)

    if(-not ($ProfileName -eq 'SystemProfile' -or $ProfileName -eq 'LocalService' -or $ProfileName -eq 'NetworkService' -or $ProfileName -like '*Service')){
        # Calculate LastLogOff time
        $LastLogOff = $null
        if($profileInfo.lastUseTime){
            $LastLogOff = [datetime]::FromFileTime($profileInfo.lastUseTime)
        }

        # Display profile name and last logoff time
        if($LastLogOff -and $LastLogOff -ne [datetime]::MinValue){
            Write-Host "  Profile: $ProfileName (Last Logoff: $($LastLogOff.ToString('dd/MM/yyyy HH:mm:ss')))"
        } else {
            Write-Host "  Profile: $ProfileName (Last Logoff: Unknown)"
        }
    }
}

# First pass to check if any orphaned profiles exist
foreach ($Profile in $ComputerProfiles) {
    $profileInfo = Get-ItemProperty -Path "$ProfilePath\$($Profile.PSChildName)" -ErrorAction SilentlyContinue
    if (-not $profileInfo -or -not (Test-Path -Path $profileInfo.ProfileImagePath)) {
        $OrphanedProfileFound = $true
        break
    }
}

# Display and process orphaned profile section only if an orphaned profile is found
if ($OrphanedProfileFound) {
    Write-Host "`nOrphaned Profile Registry Entries Found:"

    foreach ($Profile in $ComputerProfiles) {
        $profileInfo = Get-ItemProperty -Path "$ProfilePath\$($Profile.PSChildName)" -ErrorAction SilentlyContinue
        $ProfileFolderPath = $profileInfo.ProfileImagePath
        $ProfileName = Convert-SIDToUsername $Profile.PSChildName

        if ($ProfileName -and -not (Test-Path -Path $ProfileFolderPath)) {
            Write-Host "`tProfile: $ProfileName (Registry Entry: $($Profile.PSChildName))"
            
            if (-not $ReadOnlyMode) {
                try {
                    Remove-Item "$ProfilePath\$($Profile.PSChildName)" -Force
                    Write-Host "Removed registry entry for $ProfileName"
                    $RemovedRegistryEntries += $Profile.PSChildName
                } catch {
                    Write-Host "Error removing registry entry for ${ProfileName}: $_"
                }
            } else {
                Write-Host "Registry entry for $ProfileName would be removed in non-read-only mode."
            }
        }
    }
}


# Separately list profiles that will be deleted
Write-Host "`nInitiating Profile Deletion Process..."
$ProfilesToDelete = @()

$ComputerProfiles | ForEach-Object {
    # Skip processing if the registry entry was removed
    if ($_.PSChildName -in $RemovedRegistryEntries) {
        return
    }
    $profileInfo = Get-ItemProperty "$ProfilePath\$($_.PSChildName)"
    $ProfileName = [System.IO.Path]::GetFileName($profileInfo.ProfileImagePath)
    $ProfileFolderPath = $profileInfo.ProfileImagePath

    # Skip system, service, and currently logged-on user profiles
    if($ProfileName -eq 'SystemProfile' -or $ProfileName -eq 'LocalService' -or $ProfileName -eq 'NetworkService' -or $ProfileName -like '*Service' -or $LoggedOnUserPaths -contains $ProfileFolderPath){
        if($LoggedOnUserPaths -contains $ProfileFolderPath) {
            Write-Host "  Profile $ProfileName is currently logged on and will not be deleted."
        }
        return
    }

    # Calculate LastLogOff time and logoff age
    $LastLogOff = $null
    if($profileInfo.LocalProfileUnloadTimeHigh -and $profileInfo.LocalProfileUnloadTimeLow){
        [long]$NTLogoffEpoch = "0x{0:X}{1:X}" -f $profileInfo.LocalProfileUnloadTimeHigh, $profileInfo.LocalProfileUnloadTimeLow
        $LastLogOff = ([System.DateTimeOffset]::FromFileTime($NTLogoffEpoch)).DateTime
    } else {
        try {
            $LastLogOff = (Get-Item -Path $ProfileFolderPath -Force).LastWriteTime
        } catch {
            Write-Host "Error accessing profile folder for ${ProfileName}: $_"
            $LastLogOff = $null
        }
    }

    if($LastLogOff -and $LastLogOff -ne [datetime]::MinValue){
        $LogoffAgeDays = ($CurrentDate - $LastLogOff).Days

        if($LogoffAgeDays -gt $Age){
            $ProfileSize = Get-ProfileSize -ProfilePath $ProfileFolderPath
            $ProfilesToDelete += @{
                Path = $ProfileFolderPath
                SizeGB = $ProfileSize
            }
            Write-Host "  Profile $ProfileName marked for deletion: Age is $LogoffAgeDays days (Size: $ProfileSize GB)"
        } else {
            Write-Host "  Profile $ProfileName not deleted: Age is $LogoffAgeDays days"
        }
    }
}

Write-Host ""

# Delete the profiles marked for deletion
if (-not $ReadOnlyMode) {
    foreach ($Profile in $ProfilesToDelete) {
        Write-Host "Deleting profile: $($Profile.Path) ($($Profile.SizeGB) GB)"
        Remove-UserProfile -ProfilePath $Profile.Path
    }
} else {
    foreach ($Profile in $ProfilesToDelete) {
        Write-Host "Profile would be deleted in non-read-only mode: $($Profile.Path) ($($Profile.SizeGB) GB)"
    }
}

if ($ReadOnlyMode) {
    $TotalSpaceToRecover = 0
    foreach ($Profile in $ProfilesToDelete) {
        try {
            $ProfileSize = (Get-ChildItem -Path $Profile -Recurse -Force -ErrorAction Stop | Measure-Object -Property Length -Sum).Sum
            $TotalSpaceToRecover += $ProfileSize
        } catch {
            Write-Host "Error calculating size for ${Profile}: $_"
        }
    }
    $SpaceToRecoverGB = [math]::Round($TotalSpaceToRecover / 1GB, 2) # Convert bytes to GB
    Write-Host "Estimated space to recover: $SpaceToRecoverGB GB"
}

if (-not $ReadOnlyMode) {
    $InitialFreeSpace = (Get-DiskSpace).FreeSpaceGB
    foreach ($Profile in $ProfilesToDelete) {
        Write-Host "Deleting profile: $Profile"
        Remove-UserProfile -ProfilePath $Profile
    }
    $FinalFreeSpace = (Get-DiskSpace).FreeSpaceGB
    $SpaceRecovered = [math]::Round($FinalFreeSpace - $InitialFreeSpace, 2)
    Write-Host "Actual space recovered: $SpaceRecovered GB"
}

if ($ProfilesToDelete.Count -eq 0) {
    Write-Host "`nNo profiles were deleted.`n"
} elseif ($ReadOnlyMode) {
    Write-Host "`nNo profiles were deleted as script is running in read-only mode.`n"
} else {
    Write-Host "`nProfile Deletion Process Completed.`n"
}