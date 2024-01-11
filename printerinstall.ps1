Expand-Archive z99286L1b.zip -DestinationPath C:\temp\printer
pnputil /add-driver "C:\temp\printer\z99286L1b\disk1\oemsetup.inf"
Add-PrinterDriver -Name "PCL6 Driver for Universal Print"
Add-PrinterPort -Name "Downstairs Printer Port" -PrinterHostAddress 10.0.0.151
Add-Printer -DriverName "PCL6 Driver for Universal Print" -Name "Downstairs Printer" -PortName "DownstairsPrinterPort"
Set-PrintConfiguration  -PrinterName "Downstairs Printer" -Color $false -PaperSize A4