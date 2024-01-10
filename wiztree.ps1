$todaydate = Get-Date -Format "yyyy-MM-dd_HH-MM"
$env:driveletter2 = -join ("$env:driveletter", ":")
$env:outputname = "wiztree-$env:computername-$env:driveletter-$todaydate"
$env:outputnamecsv = -join ("$env:outputname", ".csv")
$env:outputnamezip = -join ("$env:outputname", ".zip")
New-Item -Path C:\ -Name "RMM" -ItemType "directory"
Start-Process -Wait -FilePath .\WizTree.exe -ArgumentList "$env:driveletter2 /export=C:\RMM\$env:outputnamecsv /admin=1 /exportallsizes=1 /exportdrivecapacity=1"
