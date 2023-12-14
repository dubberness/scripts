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

# Separately list profiles that will be deleted
Write-Host "`nProfiles Planned for Deletion:"
$ComputerProfiles | ForEach-Object {
    $profileInfo = Get-ItemProperty "$ProfilePath\$($_.PSChildName)"
    $ProfileName = [System.IO.Path]::GetFileName($profileInfo.ProfileImagePath)

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

    # Calculate logoff age and list profiles for deletion
    if($LastLogOff -and $LastLogOff -ne [datetime]::MinValue){
        $LogoffAgeDays = ($CurrentDate - $LastLogOff).Days

        # List profile if logoff age is more than 0 days
        if($LogoffAgeDays -gt 0){
            Write-Host "  Profile: $ProfileName (Last Logoff: $LastLogOff)"
        }
    }
}