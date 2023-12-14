# PowerShell Script to Check Storage Sense Settings for All Users

# Function to check Storage Sense configuration for a user
function Check-StorageSenseConfig {
    param (
        [string]$userProfilePath,
        [string]$userName
    )
    
    # Defining the registry path for the current user
    $storageSenseRegPath = "$userProfilePath\NTUSER.DAT"
    $regKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy"

    # Load the user's registry hive
    try {
        REG LOAD HKU\TempUser $storageSenseRegPath | Out-Null
    }
    catch {
        Write-Host "Unable to load registry hive for $userName"
        return
    }

    # Reading the settings
    New-PSDrive -PSProvider Registry -Root HKEY_USERS -Name HKU -ErrorAction SilentlyContinue
    if (Test-Path "HKU\TempUser\$regKey") {
        Write-Host "Storage Sense settings for $userName;"
        $settings = Get-ItemProperty -Path "HKU\TempUser\$regKey"
        [PSCustomObject]@{
            "Enable Storage Sense" = $settings."01"
            "Run Interval" = $settings."2048"
            "Delete Temp Files" = $settings."04"
            "Delete Recycle Bin Content" = $settings."08"
            "Delete Recycle Bin Interval" = $settings."256"
            "Delete Downloads Content" = $settings."32"
            "Delete Downloads Interval" = $settings."512"
        } | Format-Table -AutoSize
    }
    else {
        Write-Host "Storage Sense is not configured for $userName"
    }

    # Unloading the user's registry hive
    REG UNLOAD HKU\TempUser | Out-Null
}

# Enumerate all user profiles
$userProfiles = Get-WmiObject -Class Win32_UserProfile | Where-Object { -not $_.Special }

# Check Storage Sense settings for each user profile
foreach ($profile in $userProfiles) {
    Check-StorageSenseConfig -userProfilePath $profile.LocalPath -userName $profile.LocalPath.Split('\')[-1]
}
