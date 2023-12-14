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
Write-Host "Found the following Profiles:"

# Iterate over each profile
$ComputerProfiles | ForEach-Object {
    # Retrieve profile information
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

    # Check if $LastLogOff is a valid date and calculate logoff age
    $LogoffAgeDays = $null
    if($LastLogOff -and $LastLogOff -ne [datetime]::MinValue){
        $LogoffAgeDays = ($CurrentDate - $LastLogOff).Days
    }

    # Skip profiles with a logoff age of 0 days
    if($LogoffAgeDays -eq 0){
        return
    }

    # Output profile details if above conditions are not met
    if($LastLogOff){
        Write-Host "Profile: $($profileInfo.ProfileImagePath)"
        Write-Host "Last Logoff Age: $($LogoffAgeDays) days"
    }
}

Write-Host "`n Deleting profiles:"

foreach($Profile in $ComputerProfiles){
    $NTLogonEpoch = $null
    $LastLogOn = $null
    $NTLogoffEpoch = $null
    $LastLogOff = $null
    $Delete = $null
    $Keep = $false
    $ProfileValues = Get-ItemProperty "$ProfilePath\$($Profile.PSChildName)"

    $ProfileName = [System.IO.Path]::GetFileName($ProfileValues.ProfileImagePath)
    if($ProfileName -eq 'SystemProfile' -or $ProfileName -eq 'LocalService' -or $ProfileName -eq 'NetworkService'){
        Write-Host "Skipping system profile: $ProfileName"
        continue
    }
    if(($ProfileValues.LocalProfileLoadTimeHigh) -and ($ProfileValues.LocalProfileLoadTimeLow)){
        [long]$NTLogonEpoch = "0x{0:X}{1:X}" -f $ProfileValues.LocalProfileLoadTimeHigh, $ProfileValues.LocalProfileLoadTimeLow
        $LastLogOn = ([System.DateTimeOffset]::FromFileTime($NTLogonEpoch)).DateTime
        
        if(($LastLogOn -lt $AgeDate) -and ($LastLogOn -gt $AgeMaxThreshold)){
            $Delete = "Logon Date"
        } else{
            $Keep = $true
        }
    }
    if(($ProfileValues.LocalProfileUnloadTimeHigh) -and ($ProfileValues.LocalProfileUnloadTimeLow)){
        [long]$NTLogoffEpoch = "0x{0:X}{1:X}" -f $ProfileValues.LocalProfileUnloadTimeHigh, $ProfileValues.LocalProfileUnloadTimeLow
        $LastLogOff = ([System.DateTimeOffset]::FromFileTime($NTLogoffEpoch)).DateTime
        
        if(($LastLogOff -lt $AgeDate) -and ($LastLogOff -gt $AgeMaxThreshold)){
            $Delete = "Logoff Date"
        } else{
            $Keep = $true
        }
    }
    try{
        # Get the user account name from SID
        $objSID = New-Object System.Security.Principal.SecurityIdentifier("$($Profile.PSChildName)")
        $UserID = $objSID.Translate([System.Security.Principal.NTAccount])
    } catch [System.Management.Automation.MethodInvocationException]{
        Write-Host -Entry "$($Profile.PSChildName) does not exist for profile $($ProfileValues.ProfileImagePath)" -EntryType 2
        $UserID = 'Unknown'
    }
    if(!$Delete -and !$Keep -and ($WinInstallDate -lt $AgeDate)){
        # Profile is probably a Run As, delete it.
        $Delete = "Run As Profile"
    }
    if(($Delete) -and ($UserID -notin $LoggedOnUsers)){
        # Delete the profile, capture all output streams and log it.
        $DeleteResults = (Get-CimInstance -Class Win32_UserProfile | Where-Object{ $_.SID -eq "$($Profile.PSChildName)"} | Remove-CimInstance -ErrorAction SilentlyContinue -Verbose) *>&1
        if($?){
            $Removed = $true
        } else{
            $Removed = $false
        }
        $Output = @"
UserID: $UserID
UserSID: $($Profile.PSChildName)
ProfileType: [$Delete]
Guid: $($ProfileValues.Guid)
LastLogon: $LastLogOn
LastLogoff: $LastLogOff
Output: $DeleteResults
ProfileImagePath: $($ProfileValues.ProfileImagePath)
"@
        if(!$Removed){
            Write-Log -Entry "$Output" -EntryType 3
        } else{
            Write-Log -Entry "$Output" -EntryType 1
            Write-Host "Successfully removed profile for $UserID"
        }
    }
}