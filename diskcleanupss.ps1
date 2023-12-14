# PowerShell Script to Enable and Configure Storage Sense for All Users

# Variables - Configure these according to the options listed for each option

$EnableStorageSense = [int](Get-Content env:EnableStorageSense)
# Valid options: 0 = Disable, 1 = Enable

$RunInterval = [int](Get-Content env:RunInterval)
# Valid options: 0 = When Windows decides, 1 = Every Day, 7 = Every Week, 30 = Every Month

$DeleteTempFiles = [int](Get-Content env:DeleteTempFiles)
# Valid options: 0 = Disable, 1 = Enable

$DeleteRecycleBinContent = [int](Get-Content env:DeleteRecycleBinContent)
# Valid options: 0 = Disable, 1 = Enable 

$DeleteRecycleBinInterval = [int](Get-Content env:DeleteRecycleBinInterval)
# Valid options: 0 = Never, 1 = 1 day, 14 = 14 days, 30 = 30 days, 60 = 60 days

$DeleteDownloadsContent = [int](Get-Content env:DeleteDownloadsContent)
# Valid options: 0 = Off, 1 = On

$DeleteDownloadsInterval = [int](Get-Content env:DeleteDownloadsInterval)
# Valid options: 0 = Never, 1 = 1 day, 14 = 14 days, 30 = 30 days, 60 = 60 days

$DeleteOneDriveContent = [int](Get-Content env:DeleteOneDriveContent)
# Valid options: 0 = Off, 1 = On

$DeleteOneDriveInterval = [int](Get-Content env:DeleteOneDriveInterval)
# Valid options: 0 = Never, 1 = 1 day, 14 = 14 days, 30 = 30 days, 60 = 60 days

# Function to validate variables
function Validate-Variables {
    param(
        [int]$value,
        [int[]]$validOptions,
        [string]$variableName
    )

    if ($validOptions -notcontains $value) {
        Write-Host "Invalid value for $variableName. Must be one of: $($validOptions -join ', ')"
        exit
    }
}

# Validate variable inputs
Validate-Variables -value $EnableStorageSense -validOptions @(0, 1) -variableName 'EnableStorageSense'
Validate-Variables -value $RunInterval -validOptions @(0, 1, 7, 30) -variableName 'RunInterval'
Validate-Variables -value $DeleteTempFiles -validOptions @(0, 1) -variableName 'DeleteTempFiles'
Validate-Variables -value $DeleteRecycleBinContent -validOptions @(0, 1) -variableName 'DeleteRecycleBinContent'
Validate-Variables -value $DeleteRecycleBinInterval -validOptions @(0, 1, 14, 30, 60) -variableName 'DeleteRecycleBinInterval'
Validate-Variables -value $DeleteDownloadsContent -validOptions @(0, 1) -variableName 'DeleteDownloadsContent'
Validate-Variables -value $DeleteDownloadsInterval -validOptions @(0, 1, 14, 30, 60) -variableName 'DeleteDownloadsInterval'
Validate-Variables -value $DeleteOneDriveContent -validOptions @(0, 1) -variableName 'DeleteOneDriveContent'
Validate-Variables -value $DeleteOneDriveInterval -validOptions @(0, 1, 14, 30, 60) -variableName 'DeleteOneDriveInterval'

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
    Set-ItemProperty -Path "HKU\TempUser\$regKey" -Name "01" -Type DWord -Value $EnableStorageSense
    Set-ItemProperty -Path "HKU\TempUser\$regKey" -Name "2048" -Type DWord -Value $RunInterval
    Set-ItemProperty -Path "HKU\TempUser\$regKey" -Name "04" -Type DWord -Value $DeleteTempFiles
    Set-ItemProperty -Path "HKU\TempUser\$regKey" -Name "08" -Type DWord -Value $DeleteRecycleBinContent
    Set-ItemProperty -Path "HKU\TempUser\$regKey" -Name "256" -Type DWord -Value $DeleteRecycleBinInterval
    Set-ItemProperty -Path "HKU\TempUser\$regKey" -Name "32" -Type DWord -Value $DeleteDownloadsContent
    Set-ItemProperty -Path "HKU\TempUser\$regKey" -Name "512" -Type DWord -Value $DeleteDownloadsInterval
    # OneDrive configuration
    if ($DeleteOneDriveContent -eq 1) {
        $oneDriveKey = "HKU\TempUser\Software\Microsoft\OneDrive\Accounts"
        if (Test-Path $oneDriveKey) {
            $oneDriveAccounts = Get-ChildItem $oneDriveKey
            foreach ($account in $oneDriveAccounts) {
                $providerKeyString = "OneDrive!TempUser!" + $account.PSChildName
                $providerKeyPath = "$regKey\$providerKeyString"
                New-Item -Path $providerKeyPath -Force | Out-Null
                New-ItemProperty -Path $providerKeyPath -Name "02" -Value $DeleteOneDriveContent -Type DWord -Force
                New-ItemProperty -Path $providerKeyPath -Name "128" -Value $DeleteOneDriveInterval -Type DWord -Force
            }
        }
    }

    # Unloading the user's registry hive
    REG UNLOAD HKU\TempUser
}

# Enumerate all user profiles
$userProfiles = Get-WmiObject -Class Win32_UserProfile | Where-Object { -not $_.Special }

# Apply Storage Sense settings for each user profile
foreach ($profile in $userProfiles) {
    Apply-StorageSenseConfig -userProfilePath $profile.LocalPath
}
