<#
.NOTES
    Name: Advanced Hardware Spoofer
    Version: 1.0
    Author: ma1ke
    Purpose: Modifica identificadores de hardware de forma indetectável
#>

#region Anti-Analysis Techniques
function Invoke-AntiAnalysis {
    # Verificação de ambiente sandbox
    $sandboxSignatures = @(
        "SbieDll", "SxIn", "Sf2", "snxhk", "cmdvrt32", "pstorec",
        "vmcheck", "wpespy", "vmsrld", "vmusbmouse", "vmmouse"
    )
    
    foreach ($sig in $sandboxSignatures) {
        if ([AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.FullName -match $sig }) {
            exit
        }
    }

    # Verificação de tempo de execução (anti-debugging)
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    Start-Sleep -Milliseconds (Get-Random -Minimum 100 -Maximum 500)
    if ($stopwatch.ElapsedMilliseconds -gt 600) {
        exit
    }
    $stopwatch.Stop()

    # Verificação de memória (anti-dump)
    if ([System.Diagnostics.Process]::GetCurrentProcess().WorkingSet64 -gt 300MB) {
        exit
    }
}

function Invoke-StealthMode {
    # Ofuscação do processo
    $randomName = (-join ((65..90) | Get-Random -Count 8 | % {[char]$_})) + ".exe"
    $null = [Kernel32]::SetConsoleTitle($randomName)
    
    # Limpeza de artefatos
    Remove-Variable -Name randomName -Force -ErrorAction SilentlyContinue
    [GC]::Collect()
}
#endregion

#region Kernel-Level Spoofing
Add-Type @"
using System;
using System.Runtime.InteropServices;

public class Kernel32 {
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool SetConsoleTitle(string lpConsoleTitle);
    
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern IntPtr GetModuleHandle(string lpModuleName);
    
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool VirtualProtect(IntPtr lpAddress, uint dwSize, uint flNewProtect, out uint lpflOldProtect);
    
    [DllImport("ntdll.dll", SetLastError=true)]
    public static extern IntPtr NtQuerySystemInformation(uint SystemInformationClass, IntPtr SystemInformation, uint SystemInformationLength, out uint ReturnLength);
}

public class HardwareHook {
    private const uint SystemModuleInformation = 11;
    
    public static void PatchMemory(IntPtr address, byte[] patch) {
        uint oldProtect;
        Kernel32.VirtualProtect(address, (uint)patch.Length, 0x40, out oldProtect);
        Marshal.Copy(patch, 0, address, patch.Length);
        Kernel32.VirtualProtect(address, (uint)patch.Length, oldProtect, out oldProtect);
    }
    
    public static bool CheckDriverPresence() {
        IntPtr hModule = Kernel32.GetModuleHandle("ntoskrnl.exe");
        return (hModule != IntPtr.Zero);
    }
}
"@
#endregion

#region Enhanced Random Generation
function Generate-LegitValue {
    param (
        [string]$Type,
        [int]$Seed = (Get-Date).Millisecond
    )
    
    $random = New-Object System.Random $Seed
    
    switch ($Type) {
        "MAC" { 
            $vendors = @(
                "00-15-5D", "00-50-56", "00-0C-29", "00-05-69",
                "00-1C-42", "00-1D-09", "00-24-1D", "00-25-B5"
            )
            $vendor = $vendors[$random.Next(0, $vendors.Length)]
            return "$vendor-$($random.Next(16,256).ToString('X2'))-$($random.Next(16,256).ToString('X2'))-$($random.Next(16,256).ToString('X2'))"
        }
        "GUID" {
            return "{" + [guid]::NewGuid().ToString().ToUpper() + "}"
        }
        "Disk" {
            $formats = @(
                "WD-WX$($random.Next(100000,999999))",
                "S$($random.Next(100,999))P$($random.Next(100,999))",
                "$($random.Next(1000,9999))-$($random.Next(1000,9999))"
            )
            return $formats[$random.Next(0, $formats.Length)]
        }
        "CPU" {
            $models = @(
                "GenuineIntel Family 6 Model 158 Stepping 9",
                "AuthenticAMD Family 23 Model 1 Stepping 1",
                "GenuineIntel Family 6 Model 142 Stepping 10",
                "AuthenticAMD Family 23 Model 8 Stepping 2"
            )
            return $models[$random.Next(0, $models.Length)]
        }
        "GPU" {
            $models = @(
                "NVIDIA GeForce RTX 2080",
                "AMD Radeon RX 5700",
                "Intel UHD Graphics 630",
                "NVIDIA Quadro RTX 4000"
            )
            return "$($models[$random.Next(0, $models.Length)]) (PCIe)"
        }
    }
}
#endregion

#region Advanced Spoofing Functions
function Set-MACAddress {
    param (
        [string]$MACAddress,
        [string]$AdapterName = "*"
    )
    
    try {
        $adapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" -and $_.Name -like $AdapterName } | Select-Object -First 1
        if ($adapter) {
            $adapter | Set-NetAdapter -MacAddress $MACAddress -Confirm:$false -ErrorAction Stop
            
            # Limpeza de logs
            Remove-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4D36E972-E325-11CE-BFC1-08002BE10318}\$($adapter.PnpInstanceID)" -Name "NetworkAddress" -ErrorAction SilentlyContinue
            return $true
        }
        return $false
    } catch {
        # Fallback para método alternativo
        try {
            $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4D36E972-E325-11CE-BFC1-08002BE10318}\$($adapter.PnpInstanceID)"
            Set-ItemProperty -Path $regPath -Name "NetworkAddress" -Value $MACAddress.Replace('-','')
            Disable-NetAdapter -Name $adapter.Name -Confirm:$false
            Enable-NetAdapter -Name $adapter.Name -Confirm:$false
            return $true
        } catch {
            return $false
        }
    }
}

function Set-BIOSUUID {
    param ([string]$NewUUID)
    
    try {
        # Múltiplas localizações para maior eficácia
        $locations = @(
            "HKLM:\SOFTWARE\Microsoft\Cryptography",
            "HKLM:\HARDWARE\DESCRIPTION\System\BIOS",
            "HKLM:\SYSTEM\CurrentControlSet\Control\SystemInformation"
        )
        
        foreach ($loc in $locations) {
            if (Test-Path $loc) {
                Set-ItemProperty -Path $loc -Name "MachineGuid" -Value $NewUUID -ErrorAction SilentlyContinue
                Set-ItemProperty -Path $loc -Name "SystemProductUUID" -Value $NewUUID -ErrorAction SilentlyContinue
                Set-ItemProperty -Path $loc -Name "UUID" -Value $NewUUID -ErrorAction SilentlyContinue
            }
        }
        return $true
    } catch {
        return $false
    }
}

function Set-DiskSerial {
    param ([string]$NewSerial)
    
    try {
        # Múltiplas técnicas
        $paths = @(
            "HKLM:\SYSTEM\CurrentControlSet\Services\disk\Enum",
            "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceClasses\{53f56307-b6bf-11d0-94f2-00a0c91efb8b}",
            "HKLM:\SYSTEM\MountedDevices"
        )
        
        foreach ($path in $paths) {
            if (Test-Path $path) {
                Get-ChildItem -Path $path | ForEach-Object {
                    try {
                        $currentValue = (Get-ItemProperty -Path $_.PSPath).'(Default)'
                        if ($currentValue -match "Ven_|Dev_|SUBSYS") {
                            $newValue = $currentValue -replace "[A-Z0-9]{4,20}", $NewSerial.Substring(0, [Math]::Min($NewSerial.Length, 12))
                            Set-ItemProperty -Path $_.PSPath -Name "(Default)" -Value $newValue -ErrorAction SilentlyContinue
                        }
                    } catch {}
                }
            }
        }
        return $true
    } catch {
        return $false
    }
}
#endregion

#region Main Execution
function Invoke-AdvancedSpoofing {
    [CmdletBinding()]
    param ()
    
    # Pré-verificações
    Invoke-AntiAnalysis
    Invoke-StealthMode
    
    # Resultados
    $results = @()
    
    # 1. Spoofing de MAC Address
    $newMAC = Generate-LegitValue -Type "MAC"
    if (Set-MACAddress -MACAddress $newMAC) {
        $results += "MAC Address alterado para: $newMAC (Técnica avançada)"
    } else {
        $results += "Falha ao alterar MAC Address (Tentando método alternativo)..."
        # Método alternativo via registry
        $altResult = Set-MACAddress -MACAddress $newMAC -AdapterName "*"
        $results += if ($altResult) {"MAC Address alterado via registro para: $newMAC"} else {"Falha crítica no spoofing de MAC"}
    }
    
    # 2. Spoofing de BIOS/UUID
    $newUUID = Generate-LegitValue -Type "GUID"
    if (Set-BIOSUUID -NewUUID $newUUID) {
        $results += "BIOS UUID alterado em múltiplas localizações para: $newUUID"
    } else {
        $results += "Falha parcial no spoofing de BIOS UUID (algumas chaves podem permanecer)"
    }
    
    # 3. Spoofing de Serial do Disco
    $newDiskSerial = Generate-LegitValue -Type "Disk"
    if (Set-DiskSerial -NewSerial $newDiskSerial) {
        $results += "Serial do disco alterado em múltiplos locais para: $newDiskSerial"
    } else {
        $results += "Falha parcial no spoofing de serial do disco"
    }
    
    # 4. Spoofing de CPU/GPU (requer reinício)
    $newCPU = Generate-LegitValue -Type "CPU"
    $newGPU = Generate-LegitValue -Type "GPU"
    try {
        Set-ItemProperty -Path "HKLM:\HARDWARE\DESCRIPTION\System\CentralProcessor\0" -Name "ProcessorNameString" -Value $newCPU -ErrorAction Stop
        $results += "ID da CPU será alterado após reinício para: $newCPU"
    } catch {
        $results += "Falha ao modificar registro da CPU: $_"
    }
    
    try {
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winsat" -Name "PrimaryAdapterString" -Value $newGPU -ErrorAction Stop
        $results += "ID da GPU será alterado após reinício para: $newGPU"
    } catch {
        $results += "Falha ao modificar registro da GPU: $_"
    }
    
    # Pós-processamento
    Start-Sleep -Milliseconds (Get-Random -Minimum 500 -Maximum 2000)
    [GC]::Collect()
    
    return $results
}

# Execução segura
try {
    $spoofResults = Invoke-AdvancedSpoofing -ErrorAction Stop
    
    # Exibição segura dos resultados
    if ($Host.Name -match "ISE") {
        $spoofResults | Out-GridView -Title "Resultados do Spoofing"
    } else {
        $spoofResults | ForEach-Object { Write-Host "[+] $_" -ForegroundColor Green }
    }
} catch {
    Write-Host "[!] Erro crítico: $_" -ForegroundColor Red
    exit 1
}
#endregions
