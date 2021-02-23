configuration AKSHCIHost
{
    param 
    ( 
        [string]$customRdpPort,
        [Int]$RetryCount = 20,
        [Int]$RetryIntervalSec = 30,
        [String]$targetDrive = "V",
        [String]$targetVMPath = "$targetDrive" + ":\VMs",
        [String]$baseVHDFolderPath = "$targetVMPath\base"
    ) 


    
    Import-DscResource -ModuleName 'ComputerManagementDsc' -ModuleVersion 8.4.0
    Import-DscResource -ModuleName 'xHyper-v' -ModuleVersion 3.16.0.0
    Import-DscResource -ModuleName 'StorageDSC' -ModuleVersion 5.0.1
    Import-DscResource -ModuleName 'DSCR_Shortcut' -ModuleVersion 2.1.1
    Import-DscResource -ModuleName 'xCredSSP' -ModuleVersion 1.3.0.0



    Node localhost
    {
        LocalConfigurationManager {
            RebootNodeIfNeeded = $true
            ActionAfterReboot  = 'ContinueConfiguration'
            ConfigurationMode  = 'ApplyOnly'
        }
        
        
        
        
        
        # STAGE 1 -> PRE-HYPER-V REBOOT
        # STAGE 2 -> POST-HYPER-V REBOOT
        # STAGE 3 -> POST CREDSSP REBOOT

        #### STAGE 1a - CREATE STORAGE SPACES V: & VM FOLDER ####

        Script StoragePool {
            SetScript  = {
                New-StoragePool -FriendlyName AksHciPool -StorageSubSystemFriendlyName '*storage*' -PhysicalDisks (Get-PhysicalDisk -CanPool $true)
            }
            TestScript = {
                (Get-StoragePool -ErrorAction SilentlyContinue -FriendlyName AksHciPool).OperationalStatus -eq 'OK'
            }
            GetScript  = {
                @{Ensure = if ((Get-StoragePool -FriendlyName AksHciPool).OperationalStatus -eq 'OK') { 'Present' } Else { 'Absent' } }
            }
        }
        Script VirtualDisk {
            SetScript  = {
                $disks = Get-StoragePool -FriendlyName AksHciPool -IsPrimordial $False | Get-PhysicalDisk
                $diskNum = $disks.Count
                New-VirtualDisk -StoragePoolFriendlyName AksHciPool -FriendlyName AksHciDisk -ResiliencySettingName Simple -NumberOfColumns $diskNum -UseMaximumSize
            }
            TestScript = {
                (Get-VirtualDisk -ErrorAction SilentlyContinue -FriendlyName AksHciDisk).OperationalStatus -eq 'OK'
            }
            GetScript  = {
                @{Ensure = if ((Get-VirtualDisk -FriendlyName AksHciDisk).OperationalStatus -eq 'OK') { 'Present' } Else { 'Absent' } }
            }
            DependsOn  = "[Script]StoragePool"
        }
        Script FormatDisk {
            SetScript  = {
                $vDisk = Get-VirtualDisk -FriendlyName AksHciDisk
                if ($vDisk | Get-Disk | Where-Object PartitionStyle -eq 'raw') {
                    $vDisk | Get-Disk | Initialize-Disk -Passthru | New-Partition -DriveLetter $Using:targetDrive -UseMaximumSize | Format-Volume -NewFileSystemLabel AksHciData -AllocationUnitSize 64KB -FileSystem NTFS
                }
                elseif ($vDisk | Get-Disk | Where-Object PartitionStyle -eq 'GPT') {
                    $vDisk | Get-Disk | New-Partition -DriveLetter $Using:targetDrive -UseMaximumSize | Format-Volume -NewFileSystemLabel AksHciData -AllocationUnitSize 64KB -FileSystem NTFS
                }
            }
            TestScript = { 
                (Get-Volume -ErrorAction SilentlyContinue -FileSystemLabel AksHciData).FileSystem -eq 'NTFS'
            }
            GetScript  = {
                @{Ensure = if ((Get-Volume -FileSystemLabel AksHciData).FileSystem -eq 'NTFS') { 'Present' } Else { 'Absent' } }
            }
            DependsOn  = "[Script]VirtualDisk"
        }

        File "VMfolder" {
            Type            = 'Directory'
            DestinationPath = $targetVMPath
            DependsOn       = "[Script]FormatDisk"
        }

        if ($environment -eq "AD Domain") {
            File "ADfolder" {
                Type            = 'Directory'
                DestinationPath = $targetADPath
                DependsOn       = "[Script]FormatDisk"
            }
        }


#### STAGE 1b - SET WINDOWS DEFENDER EXCLUSION FOR VM STORAGE ####

Script defenderExclusions {
    SetScript  = {
        $exclusionPath = "$Using:targetDrive" + ":\"
        Add-MpPreference -ExclusionPath "$exclusionPath"               
    }
    TestScript = {
        $exclusionPath = "$Using:targetDrive" + ":\"
        (Get-MpPreference).ExclusionPath -contains "$exclusionPath"
    }
    GetScript  = {
        $exclusionPath = "$Using:targetDrive" + ":\"
        @{Ensure = if ((Get-MpPreference).ExclusionPath -contains "$exclusionPath") { 'Present' } Else { 'Absent' } }
    }
    DependsOn  = "[File]VMfolder"
}

#### STAGE 1c - REGISTRY & SCHEDULED TASK TWEAKS ####

Registry "Disable Internet Explorer ESC for Admin" {
    Key       = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}"
    Ensure    = 'Present'
    ValueName = "IsInstalled"
    ValueData = "0"
    ValueType = "Dword"
}

Registry "Disable Internet Explorer ESC for User" {
    Key       = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}"
    Ensure    = 'Present'
    ValueName = "IsInstalled"
    ValueData = "0"
    ValueType = "Dword"
}

Registry "Disable Server Manager WAC Prompt" {
    Key       = "HKLM:\SOFTWARE\Microsoft\ServerManager"
    Ensure    = 'Present'
    ValueName = "DoNotPopWACConsoleAtSMLaunch"
    ValueData = "1"
    ValueType = "Dword"
}

Registry "Disable Network Profile Prompt" {
    Key       = 'HKLM:\System\CurrentControlSet\Control\Network\NewNetworkWindowOff'
    Ensure    = 'Present'
    ValueName = ''
}

if ($environment -eq "Workgroup") {
    Registry "Set Network Private Profile Default" {
        Key       = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\CurrentVersion\NetworkList\Signatures\010103000F0000F0010000000F0000F0C967A3643C3AD745950DA7859209176EF5B87C875FA20DF21951640E807D7C24'
        Ensure    = 'Present'
        ValueName = "Category"
        ValueData = "1"
        ValueType = "Dword"
    }

    Registry "SetWorkgroupDomain" {
        Key       = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"
        Ensure    = 'Present'
        ValueName = "Domain"
        ValueData = "$DomainName"
        ValueType = "String"
    }

    Registry "SetWorkgroupNVDomain" {
        Key       = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"
        Ensure    = 'Present'
        ValueName = "NV Domain"
        ValueData = "$DomainName"
        ValueType = "String"
    }

    Registry "NewCredSSPKey" {
        Key       = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation\AllowFreshCredentialsWhenNTLMOnly'
        Ensure    = 'Present'
        ValueName = ''
    }

    Registry "NewCredSSPKey2" {
        Key       = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation'
        ValueName = 'AllowFreshCredentialsWhenNTLMOnly'
        ValueData = '1'
        ValueType = "Dword"
        DependsOn = "[Registry]NewCredSSPKey"
    }

    Registry "NewCredSSPKey3" {
        Key       = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CredentialsDelegation\AllowFreshCredentialsWhenNTLMOnly'
        ValueName = '1'
        ValueData = "*.$DomainName"
        ValueType = "String"
        DependsOn = "[Registry]NewCredSSPKey2"
    }
}

ScheduledTask "Disable Server Manager at Startup" {
    TaskName = 'ServerManager'
    Enable   = $false
    TaskPath = '\Microsoft\Windows\Server Manager'
}

#### STAGE 1d - CUSTOM FIREWALL BASED ON ARM TEMPLATE ####

if ($customRdpPort -ne "3389") {

    Registry "Set Custom RDP Port" {
        Key       = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp'
        ValueName = "PortNumber"
        ValueData = "$customRdpPort"
        ValueType = 'Dword'
    }

    Firewall AddFirewallRule {
        Name        = 'CustomRdpRule'
        DisplayName = 'Custom Rule for RDP'
        Ensure      = 'Present'
        Enabled     = 'True'
        Profile     = 'Any'
        Direction   = 'Inbound'
        LocalPort   = "$customRdpPort"
        Protocol    = 'TCP'
        Description = 'Firewall Rule for Custom RDP Port'
    }
}

#### STAGE 1e - ENABLE ROLES & FEATURES ####

WindowsFeature "Enable Deduplication" { 
    Ensure = "Present" 
    Name   = "FS-Data-Deduplication"		
}

{
    WindowsFeature "Hyper-V" {
        Name      = "Hyper-V"
        Ensure    = "Present"
        DependsOn = "[Registry]NewCredSSPKey3"
    }
}

WindowsFeature "RSAT-Hyper-V-Tools" {
    Name      = "RSAT-Hyper-V-Tools"
    Ensure    = "Present"
    DependsOn = "[WindowsFeature]Hyper-V" 
}


 #### STAGE 2h - CONFIGURE CREDSSP & WinRM

 xCredSSP Server {
    Ensure         = "Present"
    Role           = "Server"
    DependsOn      = "[DnsConnectionSuffix]AddSpecificSuffixNATNic"
    SuppressReboot = $true
}
xCredSSP Client {
    Ensure            = "Present"
    Role              = "Client"
    DelegateComputers = "$env:COMPUTERNAME" + ".$DomainName"
    DependsOn         = "[xCredSSP]Server"
    SuppressReboot    = $true
}

#### STAGE 3a - CONFIGURE WinRM

Script ConfigureWinRM {
    SetScript  = {
        Set-Item WSMan:\localhost\Client\TrustedHosts "*.$Using:DomainName" -Force
    }
    TestScript = {
        (Get-Item WSMan:\localhost\Client\TrustedHosts).Value -contains "*.$Using:DomainName"
    }
    GetScript  = {
        @{Ensure = if ((Get-Item WSMan:\localhost\Client\TrustedHosts).Value -contains "*.$Using:DomainName") { 'Present' } Else { 'Absent' } }
    }
    DependsOn  = "[xCredSSP]Client"
}
}






































}