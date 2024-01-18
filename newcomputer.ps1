$wingetPackages = @(
'Google.Chrome'
'Adobe.Acrobat.Reader.32-bit'
'7zip.7zip'
)

# Try winget command
try
{
	winget | out-null
}
catch
{
	Install-Winget
}
# Try winget command again
try
{
	winget | out-null
}
catch
{
	Throw "Winget not installed ; ending script"
	break
}


# Foreach loop to install packages

foreach ($package in $wingetPackages){
Write-Host "Installing Winget Package $($package)" -ForegroundColor Green -BackgroundColor Black
WingetRun -RunType Install -PackageID $package
}

# Show all items in system tray
Set-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer -Name EnableAutoTray -Value 0 -Force

# Show file extensions in explorer
Set-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name HiddFileExt -Value 0

Set-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced -Name HiddeIcons -Value 0

# Unpin Mail App and Windows Store
UnPin-AppFromTaskBar -AppName "Microsoft Store" -Verb taskbarunpin
UnPin-AppFromTaskBar -AppName Mail -Verb taskbarunpin

# Pin Apps to taskbar
$StartMenuFolder = "$env:programdata\Microsoft\Windows\Start Menu\Programs"
Pin-ToTaskbar -targetfile "$StartMenuFolder\Google Chrome.lnk" -Action pin