param(
    [string]$OutDir = "$(Split-Path -Parent $MyInvocation.MyCommand.Definition)\inventarios"
)

# Criar diretório com timestamp
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$hostname = $env:COMPUTERNAME
$targetDir = Join-Path $OutDir "$hostname`_$timestamp"
New-Item -ItemType Directory -Path $targetDir -Force | Out-Null

# Função para salvar JSON
function Save-Json {
    param($obj, $filename)
    $json = $obj | ConvertTo-Json -Depth 10
    $path = Join-Path $targetDir $filename
    $json | Out-File -FilePath $path -Encoding UTF8
    Write-Host "Arquivo salvo: $path"
}

# 1. Informações do sistema
$system = @{
    Hostname = $hostname
    Timestamp = $timestamp
    OS = Get-CimInstance -ClassName Win32_OperatingSystem |
         Select-Object Caption, Version, OSArchitecture, InstallDate
    BIOS = Get-CimInstance -ClassName Win32_BIOS |
         Select-Object Manufacturer, SMBIOSBIOSVersion, SerialNumber
    Computer = Get-CimInstance -ClassName Win32_ComputerSystem |
         Select-Object Manufacturer, Model, TotalPhysicalMemory
}

# 2. Programas instalados
$installed = @()
$regPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
)
foreach ($path in $regPaths) {
    try {
        Get-ItemProperty -Path $path -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName } |
        Select-Object DisplayName, DisplayVersion, Publisher, InstallDate |
        ForEach-Object {
            $installed += @{
                Name = $_.DisplayName
                Version = $_.DisplayVersion
                Publisher = $_.Publisher
                InstallDate = $_.InstallDate
            }
        }
    } catch {}
}

# 3. IPs e adaptadores de rede
try {
    $network = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
        Where-Object { $_.IPAddress -ne "127.0.0.1" } |
        Select-Object InterfaceAlias, IPAddress, InterfaceIndex, AddressState
} catch {
    $network = ipconfig /all | Out-String
}

# 4. Usuários locais
try {
    $users = Get-LocalUser | Select-Object Name, Enabled, LastLogon
} catch {
    $users = Get-CimInstance Win32_UserAccount | Where-Object { $_.LocalAccount } |
             Select-Object Name, Status, Disabled
}

# 5. Memória (RAM)
$memoryModules = Get-CimInstance -ClassName Win32_PhysicalMemory |
    Select-Object BankLabel, Capacity, Speed, Manufacturer, PartNumber
$memory = @{
    TotalPhysicalMemoryGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 2)
    Modules = $memoryModules
}

# 6. Discos e volumes
$disks = Get-CimInstance Win32_DiskDrive |
    Select-Object Model, Size, InterfaceType, MediaType, SerialNumber
$volumes = Get-CimInstance Win32_LogicalDisk |
    Select-Object DeviceID, VolumeName, FileSystem, Size, FreeSpace
$storage = @{ Disks = $disks; Volumes = $volumes }

# 7. Dispositivos USB
try {
    $usbDevices = Get-PnpDevice -Class USB -Status OK |
        Select-Object InstanceId, FriendlyName, Manufacturer
} catch {
    $usbDevices = Get-CimInstance Win32_PnPEntity |
        Where-Object { $_.DeviceID -like "USB*" } |
        Select-Object Name, Manufacturer, DeviceID
}
$usbStorage = Get-CimInstance Win32_DiskDrive |
    Where-Object { $_.InterfaceType -eq "USB" } |
    Select-Object Model, SerialNumber, Size, MediaType
$usb = @{ Devices = $usbDevices; Storage = $usbStorage }

# JSON final (sem runtime)
$inventario = @{
    Hostname = $hostname
    Timestamp = $timestamp
    SystemInfo = $system
    InstalledPrograms = $installed
    Network = $network
    LocalUsers = $users
    Memory = $memory
    Storage = $storage
    USB = $usb
}

# Salvar como JSON
Save-Json -obj $inventario -filename "inventario_completo_$hostname.json"
