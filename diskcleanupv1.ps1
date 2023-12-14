param(
    [uint32]$Age = $env:profileage
)

#Welcome the user
Write-Host "Hello friend! Welcome to Ben's disk cleanup script :)`n"

$AgeDate = (Get-Date).AddDays(-$Age)
$AgeMaxThreshold = (Get-Date).AddYears(-5)
$ProfilePath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList"
$ComputerProfiles = Get-ChildItem "$ProfilePath"
$LoggedOnUsers = Get-CimInstance Win32_Process -Filter "name like 'explorer.exe'" | Invoke-CimMethod -MethodName GetOwner -ErrorAction SilentlyContinue | Select-Object -ExpandProperty User -Unique
$WinInstallDate = (Get-CimInstance Win32_OperatingSystem).InstallDate
$CurrentDate = Get-Date

# Start of profile analysis
Write-Host "Scanning for Profiles..."

# List all non-system profiles
Write-Host "Non-System Profiles Found:"
$ComputerProfiles | ForEach-Object {
    $profileInfo = Get-ItemProperty "$ProfilePath\$($_.PSChildName)"
    $ProfileName = [System.IO.Path]::GetFileName($profileInfo.ProfileImagePath)

    if(-not ($ProfileName -eq 'SystemProfile' -or $ProfileName -eq 'LocalService' -or $ProfileName -eq 'NetworkService' -or $ProfileName -like '*Service')){
        Write-Host "  Profile: $ProfileName"
    }
}

# Function to safely delete a user profile
function Remove-UserProfile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProfilePath
    )

    try {
        # Attempt to remove the user profile
        Remove-Item -Path $ProfilePath -Recurse -Force
        Write-Host "Successfully deleted profile at: $ProfilePath"
    } catch {
        # Output an error message if the deletion fails
        Write-Host "Error deleting profile at: $ProfilePath. Error: $_"
    }
}

# Separately list profiles that will be deleted
Write-Host "`nInitiating Profile Deletion Process..."
$ProfilesToDelete = @()

$ComputerProfiles | ForEach-Object {
    $profileInfo = Get-ItemProperty "$ProfilePath\$($_.PSChildName)"
    $ProfileName = [System.IO.Path]::GetFileName($profileInfo.ProfileImagePath)
    $ProfileFolderPath = $profileInfo.ProfileImagePath

    # Skip system and service profiles silently
    if($ProfileName -eq 'SystemProfile' -or $ProfileName -eq 'LocalService' -or $ProfileName -eq 'NetworkService' -or $ProfileName -like '*Service'){
        return
    }

    # Calculate LastLogOff time
    $NTLogoffEpoch = $null
    $LastLogOff = $null
    if($profileInfo.LocalProfileUnloadTimeHigh -and $profileInfo.LocalProfileUnloadTimeLow){
        [long]$NTLogoffEpoch = "0x{0:X}{1:X}" -f $profileInfo.LocalProfileUnloadTimeHigh, $profileInfo.LocalProfileUnloadTimeLow
        $LastLogOff = ([System.DateTimeOffset]::FromFileTime($NTLogoffEpoch)).DateTime
    }

    # Calculate logoff age and add profiles for deletion
    if($LastLogOff -and $LastLogOff -ne [datetime]::MinValue){
        $LogoffAgeDays = ($CurrentDate - $LastLogOff).Days

        # Add profile to deletion list if logoff age is more than the set threshold
        if($LogoffAgeDays -gt $Age){
            $ProfilesToDelete += $ProfileFolderPath
            Write-Host "Profile marked for deletion: $ProfileName (Last Logoff: $LastLogOff)"
        }
    }
}

# Delete the profiles marked for deletion
foreach ($Profile in $ProfilesToDelete) {
    Write-Host "Deleting profile: $Profile"
    Remove-UserProfile -ProfilePath $Profile
}

Write-Host "`nProfile Deletion Process Completed."
