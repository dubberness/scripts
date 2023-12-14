<# 
    .SYNOPSIS  
    Remove unused User Profiles.
    .PARAMETER Age
    Age in days since last logon/logoff, the default is 90.
    .EXAMPLE
    PS> Remove-Profiles.ps1 -Age 30
    A value of 30 would mean any profiles that haven't been used in over 30 days will be deleted.
#>

param(
    [uint32]$Age = $env:profileage
)

$logSource = "ProfileCleanup" # Something like MyScript, but not MyScript.log
$logPath = "$env:SystemRoot\Logs"
# 1 = File, 2 = Event Viewer, 3 = Both
$logTarget = 1
function Write-Log{
    param(
        [Parameter(Mandatory)]
        [string]$Entry,
        # Defines colors in CMTrace
        # 1 = Information, 2 = Warning, 3 = Error
        [ValidateSet(1, 2, 3)]
        [int]$EntryType = 1,
        [int32]$EventId = 0,
        [switch]$Raw
    )
    Switch($logTarget){
        { $_ -band 1 }{
            if($Raw){
                Add-Content -Value $Entry -Path "$logPath\$logSource.log"
            } else{
                $TimeGenerated = "$(Get-Date -Format HH:mm:ss).$((Get-Date).Millisecond)+000"
                $Line = '<![LOG[{0}]LOG]!><time="{1}" date="{2}" component="{3}" context="" type="{4}" thread="" file="">'
                $LineFormat = $Entry, $TimeGenerated, (Get-Date -Format MM-dd-yyyy), "$($MyInvocation.ScriptName | Split-Path -Leaf):$($MyInvocation.ScriptLineNumber)", $EntryType
                $Line = $Line -f $LineFormat
                Add-Content -Value $Line -Path "$logPath\$logSource.log"
            }
        }
        { $_ -band 2 }{
            $EntryTypeName = switch($EntryType){
                1 {'Information'}
                2 {'Warning'}
                3 {'Error'}
            }
            New-EventLog -LogName 'Application' -Source "$logSource" -ea SilentlyContinue
            Write-EventLog -LogName 'Application' -Source "$logSource" -EventId $EventId -EntryType $EntryTypeName -Message "$Entry" -ea SilentlyContinue
        }
    }
} #end function Write-Log

$AgeDate = (Get-Date).AddDays(-$Age)
$AgeMaxThreshold = (Get-Date).AddYears(-5)
$ProfilePath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList"
$DomainProfiles = Get-ChildItem "$ProfilePath"
$LoggedOnUsers = Get-CimInstance Win32_Process -Filter "name like 'explorer.exe'" | Invoke-CimMethod -MethodName GetOwner -ErrorAction SilentlyContinue | Select-Object -ExpandProperty User -Unique
$WinInstallDate = (Get-CimInstance Win32_OperatingSystem).InstallDate

Write-Host "Found the following Profiles:"
$DomainProfiles | ForEach-Object {
    $profileInfo = Get-ItemProperty "$ProfilePath\$($_.PSChildName)"
    
    # Modification: Check if the profile is a system profile
    $ProfileName = [System.IO.Path]::GetFileName($profileInfo.ProfileImagePath)
    if($ProfileName -eq 'SystemProfile' -or $ProfileName -eq 'LocalService' -or $ProfileName -eq 'NetworkService'){
        Write-Host "Skipping system profile: $ProfileName"
        return
    }

    # Original code to calculate LastLogOn and LastLogOff
    $NTLogonEpoch = $null
    $LastLogOn = $null
    $NTLogoffEpoch = $null
    $LastLogOff = $null
    
    if($profileInfo.LocalProfileLoadTimeHigh -and $profileInfo.LocalProfileLoadTimeLow){
        [long]$NTLogonEpoch = "0x{0:X}{1:X}" -f $profileInfo.LocalProfileLoadTimeHigh, $profileInfo.LocalProfileLoadTimeLow
        $LastLogOn = ([System.DateTimeOffset]::FromFileTime($NTLogonEpoch)).DateTime
    }

    if($profileInfo.LocalProfileUnloadTimeHigh -and $profileInfo.LocalProfileUnloadTimeLow){
        [long]$NTLogoffEpoch = "0x{0:X}{1:X}" -f $profileInfo.LocalProfileUnloadTimeHigh, $profileInfo.LocalProfileUnloadTimeLow
        $LastLogOff = ([System.DateTimeOffset]::FromFileTime($NTLogoffEpoch)).DateTime
    }

    # Modification: Print profile details excluding system profiles
    $CurrentDate = Get-Date
    $LogonAgeDays = ($CurrentDate - $LastLogOn).Days
    $LogoffAgeDays = ($CurrentDate - $LastLogOff).Days

    Write-Host "Profile: $($profileInfo.ProfileImagePath)"
    Write-Host "Last Logon Age: $($LogonAgeDays) days"
    Write-Host "Last Logoff Age: $($LogoffAgeDays) days"
}



foreach($Profile in $DomainProfiles){
    Write-Host "'n Deleting profiles:"
    Write-Log -Entry "Processing profile: $($Profile.PSChildName)" -EntryType 1
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
        Write-Log -Entry "$($Profile.PSChildName) does not exist for profile $($ProfileValues.ProfileImagePath)" -EntryType 2
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