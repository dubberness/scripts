$driverArchive = "z99286L1b.zip" #Name of .zip uploaded via RMM
$destinationPath = "C:\temp\printer"
$printerHostAddress = "10.0.0.151"
$printerName = "Downstairs Printer"
$driverPath = "$destinationPath\z99286L1b\disk1\oemsetup.inf" #Location of the .inf file
$printerDriverName = "PCL6 Driver for Universal Print" # Driver Name to be installed inside .inf file
$colorSetting = $false #True = Colour, False = Black & White
$paperSize = "A4"

Write-Host "Hello Friend!"

Try {
    Write-Host "Starting printer installation..."

    # Extracting Printer Driver
    Expand-Archive $driverArchive -DestinationPath $destinationPath -Force
    Write-Host "Extracting Printer Driver: Success"

    # Installing Printer Driver
    pnputil /add-driver $driverPath
    Write-Host "Installing Printer Driver: Success"

    # Adding Printer Driver
    Add-PrinterDriver -Name $printerDriverName
    Write-Host "Adding Printer Driver: Success"

    # Adding Printer Port
    $printerPortName = "$printerName Port"
    Add-PrinterPort -Name "$printerName Port" -PrinterHostAddress $printerHostAddress
    Write-Host "Adding Printer Port: Success"

    # Adding Printer
    Add-Printer -DriverName $printerDriverName -Name $printerName -PortName $printerPortName
    Write-Host "Adding Printer: Success"

    # Setting Print Configuration
    Set-PrintConfiguration -PrinterName $printerName -Color $colorSetting -PaperSize $paperSize
    Write-Host "Setting Print Configuration: Success"

    Write-Host "Printer installation completed successfully."
}
Catch {
    Write-Host "An error occurred during installation: $_"
}
