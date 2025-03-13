# 1. Parametry konfiguracji
# ---------------------------------
$StorageAccountName = "hemolensbackup"      # Nazwa konta magazynu Azure
$ContainerName = "backup"            # Nazwa kontenera w Azure Blob Storage
$SasToken = $env:SASTOKEN
$ComputerName = $env:COMPUTERNAME
$UserName = $env:USERNAME                      # Pobranie nazwy aktualnie zalogowanego użytkownika
$DestinationPath = "https://$StorageAccountName.blob.core.windows.net/$ContainerName/$ComputerName/$UserName"

# 2. Sprawdzenie i instalacja AzCopy (jeśli nie jest zainstalowane)
# ---------------------------------
if (-not (Get-Command azcopy -ErrorAction SilentlyContinue)) {
    Write-Host "AzCopy nie jest zainstalowane. Pobieranie i instalacja..."
    $AzCopyZipUrl = "https://aka.ms/downloadazcopy-v10-windows"
    $AzCopyZipPath = "$env:TEMP\azcopy.zip"
    $AzCopyPath = "$env:TEMP\azcopy"

    Invoke-WebRequest -Uri $AzCopyZipUrl -OutFile $AzCopyZipPath
    Expand-Archive -Path $AzCopyZipPath -DestinationPath $AzCopyPath -Force
    $AzCopyExePath = (Get-ChildItem -Path $AzCopyPath -Recurse -Filter azcopy.exe).FullName
    $env:PATH += ";$(Split-Path $AzCopyExePath)"

    Write-Host "AzCopy zostało pomyslnie zainstalowane."
} else {
    Write-Host "AzCopy jest juz zainstalowane."
}

# 3. Funkcja do kopiowania danych z dysku
function Copy-DiskData {
    param (
        [string]$DriveLetter,
        [string]$DestinationPath
    )
    
    $sourcePath = "${DriveLetter}:\"
    

$AzCopyCommand = "azcopy sync `"$sourcePath`" `"$DestinationPath/$DriveLetter$SasToken`" --recursive=true --exclude-path `"Windows;Program Files;Program Files (x86);ProgramData;Users\*\AppData\Local\Temp;$Recycle.Bin;System Volume Information;PerfLogs`" --exclude-pattern `"pagefile.sys;swapfile.sys;hiberfil.sys;*.tmp;*.temp;*.log`""


    Write-Host "Synchronizacja danych z dysku $DriveLetter..."
    Write-Host "Wykonywane polecenie: $AzCopyCommand"
    Invoke-Expression $AzCopyCommand
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Synchronizacja z dysku $DriveLetter zakonczona pomyslnie!" -ForegroundColor Green
        return "Synchronizacja z dysku $DriveLetter zakonczona pomyslnie."
    } else {
        Write-Host "Wystapil blad podczas synchronizacji z dysku $DriveLetter. Kod bledu: $LASTEXITCODE" -ForegroundColor Red
        return "Wystapil blad podczas synchronizacji z dysku $DriveLetter. Kod bledu: $LASTEXITCODE"
    }
}

# 4. Kopiowanie danych ze wszystkich lokalnych dysków
# ---------------------------------
$localDrives = Get-WmiObject Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 }
$logContent = @()

foreach ($drive in $localDrives) {
    $result = Copy-DiskData -DriveLetter $drive.DeviceID.Substring(0,1) -DestinationPath $DestinationPath
    $logContent += $result
}

# 5. Logowanie wyniku (do pliku tekstowego i do bloba)
# ---------------------------------
$LogFile = "$env:TEMP\BackupLog_$UserName.txt"
$LogMessage = "$(Get-Date): Synchronizacja danych uzytkownika '$UserName' zakonczona."
$LogMessage += $logContent -join "`n"

# Zapisywanie logu lokalnie
Add-Content -Path $LogFile -Value $LogMessage
Write-Host "Log zapisany lokalnie do: $LogFile"

# Zapisywanie logu do bloba
$TempLogFile = "$env:TEMP\TempBackupLog_$UserName.txt"
Set-Content -Path $TempLogFile -Value $LogMessage

$LogBlobName = "logs/BackupLog_$UserName_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
$LogBlobUrl = "$DestinationPath/$LogBlobName$SasToken"

azcopy copy $TempLogFile $LogBlobUrl

if ($LASTEXITCODE -eq 0) {
    Write-Host "Log zostal pomyslnie zapisany do Azure Blob Storage." -ForegroundColor Green
} else {
    Write-Host "Wystapił blad podczas zapisywania logu do Azure Blob Storage. Kod bledu: $LASTEXITCODE" -ForegroundColor Red
}

# Usuwanie tymczasowego pliku logu
Remove-Item -Path $TempLogFile -Force
