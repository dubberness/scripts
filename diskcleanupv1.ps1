param(
    [uint32]$Age = $env:profileage
)

#Welcome the user
Write-Host "`nHello friend! Welcome to Ben's disk cleanup script :)`n"

$ProfilePath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList"
$ComputerProfiles = Get-ChildItem "$ProfilePath"
$LoggedOnUsers = Get-CimInstance Win32_Process -Filter "name like 'explorer.exe'" | Invoke-CimMethod -MethodName GetOwner -ErrorAction SilentlyContinue | Select-Object -ExpandProperty User -Unique
$CurrentDate = Get-Date

# Start of profile analysis
Write-Host "Scanning for Profiles...`n"

# List all non-system profiles
Write-Host "Profiles Found:"
$ComputerProfiles | ForEach-Object {
    $profileInfo = Get-ItemProperty "$ProfilePath\$($_.PSChildName)"
    $ProfileName = [System.IO.Path]::GetFileName($profileInfo.ProfileImagePath)

    if(-not ($ProfileName -eq 'SystemProfile' -or $ProfileName -eq 'LocalService' -or $ProfileName -eq 'NetworkService' -or $ProfileName -like '*Service')){
        # Calculate LastLogOff time
        $NTLogoffEpoch = $null
        $LastLogOff = $null
        if($profileInfo.LocalProfileUnloadTimeHigh -and $profileInfo.LocalProfileUnloadTimeLow){
            [long]$NTLogoffEpoch = "0x{0:X}{1:X}" -f $profileInfo.LocalProfileUnloadTimeHigh, $profileInfo.LocalProfileUnloadTimeLow
            $LastLogOff = ([System.DateTimeOffset]::FromFileTime($NTLogoffEpoch)).DateTime
        }

        # Display profile name and last logoff time
        if($LastLogOff -and $LastLogOff -ne [datetime]::MinValue){
            Write-Host "  Profile: $ProfileName (Last Logoff: $LastLogOff)"
        } else {
            Write-Host "  Profile: $ProfileName (Last Logoff: Unknown)"
        }
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
Write-Host "`nInitiating Profile Deletion Process...`n"
$ProfilesToDelete = @()

$ComputerProfiles | ForEach-Object {
    $profileInfo = Get-ItemProperty "$ProfilePath\$($_.PSChildName)"
    $ProfileName = [System.IO.Path]::GetFileName($profileInfo.ProfileImagePath)
    $ProfileFolderPath = $profileInfo.ProfileImagePath

    # Skip system, service, and currently logged-on user profiles
    if($ProfileName -eq 'SystemProfile' -or $ProfileName -eq 'LocalService' -or $ProfileName -eq 'NetworkService' -or $ProfileName -like '*Service' -or $LoggedOnUsers -contains $ProfileName){
        if($LoggedOnUsers -contains $ProfileName) {
            Write-Host "Profile $ProfileName is currently logged on and will not be deleted."
        }
        return
    }

    # Calculate LastLogOff time and logoff age
    $NTLogoffEpoch = $null
    $LastLogOff = $null
    if($profileInfo.LocalProfileUnloadTimeHigh -and $profileInfo.LocalProfileUnloadTimeLow){
        [long]$NTLogoffEpoch = "0x{0:X}{1:X}" -f $profileInfo.LocalProfileUnloadTimeHigh, $profileInfo.LocalProfileUnloadTimeLow
        $LastLogOff = ([System.DateTimeOffset]::FromFileTime($NTLogoffEpoch)).DateTime
    }

    if($LastLogOff -and $LastLogOff -ne [datetime]::MinValue){
        $LogoffAgeDays = ($CurrentDate - $LastLogOff).Days

        if($LogoffAgeDays -gt $Age){
            $ProfilesToDelete += $ProfileFolderPath
            Write-Host "Profile marked for deletion: $ProfileName (Last Logoff: $LastLogOff)"
        } else {
            Write-Host "Profile $ProfileName not deleted: Age is $LogoffAgeDays days"
        }
    }
}

# Delete the profiles marked for deletion
foreach ($Profile in $ProfilesToDelete) {
    Write-Host "Deleting profile: $Profile"
    Remove-UserProfile -ProfilePath $Profile
}

if ($ProfilesToDelete.Count -eq 0) {
    Write-Host "`nNo profiles were deleted.`n"
} else {
    Write-Host "`nProfile Deletion Process Completed.`n"
}