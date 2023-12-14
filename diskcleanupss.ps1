# PowerShell Script to Enable and Configure Storage Sense for All Users

# Variables - Modify these within Datto RMM when deploying
$PrefSched = '7' # Options: 0 (Low Disk Space), 1, 7, 30
$ClearTemporaryFiles = 1 # 1 for true, 0 for false
$ClearRecycler = 1 # 1 for true, 0 for false
$ClearDownloads = 1 # 1 for true, 0 for false
$ClearRecyclerDays = '14' # Options: 0 (never), 1, 14, 30, 60
$ClearDownloadsDays = '30' # Options: 0 (never), 1, 14, 30, 60

# Function to apply Storage Sense configuration
function Apply-StorageSenseConfig {
    param (
        [string]$userProfilePath
    )
    
    # Defining the registry path for the current user
    $storageSenseRegPath = "$userProfilePath\NTUSER.DAT"
    $regKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy"

    # Load the user's registry hive
    REG LOAD HKU\TempUser $storageSenseRegPath

    # Applying the settings
    New-PSDrive -PSProvider Registry -Root HKEY_USERS -Name HKU -ErrorAction SilentlyContinue
    Set-ItemProperty -Path "HKU\TempUser\$regKey" -Name "01" -Type DWord -Value 1
    Set-ItemProperty -Path "HKU\TempUser\$regKey" -Name "2048" -Type DWord -Value $PrefSched
    Set-ItemProperty -Path "HKU\TempUser\$regKey" -Name "04" -Type DWord -Value $ClearTemporaryFiles
    Set-ItemProperty -Path "HKU\TempUser\$regKey" -Name "08" -Type DWord -Value $ClearRecycler
    Set-ItemProperty -Path "HKU\TempUser\$regKey" -Name "32" -Type DWord -Value $ClearDownloads
    Set-ItemProperty -Path "HKU\TempUser\$regKey" -Name "256" -Type DWord -Value $ClearRecyclerDays
    Set-ItemProperty -Path "HKU\TempUser\$regKey" -Name "512" -Type DWord -Value $ClearDownloadsDays

    # Unloading the user's registry hive
    REG UNLOAD HKU\TempUser
}

# Enumerate all user profiles
$userProfiles = Get-WmiObject -Class Win32_UserProfile | Where-Object { -not $_.Special }

# Apply Storage Sense settings for each user profile
foreach ($profile in $userProfiles) {
    Apply-StorageSenseConfig -userProfilePath $profile.LocalPath
}
