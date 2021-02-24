Configuration ASHCIHost {

    param(
    [String]$targetDrive = "V"
    )
    
    Import-DscResource -ModuleName 'PSDesiredStateConfiguration'
    
    Node localhost{

    LocalConfigurationManager {
    RebootNodeIfNeeded = $true
    ActionAfterReboot  = 'ContinueConfiguration'
    ConfigurationMode = 'ApplyOnly'
    }


    #Windows Features Installations
    WindowsFeature Hyper-V {
    Ensure = 'Present'
    Name = "Hyper-V"
    IncludeAllSubFeature = $true
    
    }
    
    WindowsFeature Hyper-V-PowerShell{
    Ensure = 'Present'
    Name='Hyper-V-PowerShell'
    IncludeAllSubFeature = $true
    }
    
#Configuring Storage Pool
    Script StoragePool {
        SetScript  = {
            New-StoragePool -FriendlyName AsHciPool -StorageSubSystemFriendlyName '*storage*' -PhysicalDisks (Get-PhysicalDisk -CanPool $true)
        }
        TestScript = {
            (Get-StoragePool -ErrorAction SilentlyContinue -FriendlyName AsHciPool).OperationalStatus -eq 'OK'
        }
        GetScript  = {
            @{Ensure = if ((Get-StoragePool -FriendlyName AsHciPool).OperationalStatus -eq 'OK') { 'Present' } Else { 'Absent' } }
        }
    }
    Script VirtualDisk {
        SetScript  = {
            $disks = Get-StoragePool -FriendlyName AsHciPool -IsPrimordial $False | Get-PhysicalDisk
            $diskNum = $disks.Count
            New-VirtualDisk -StoragePoolFriendlyName AsHciPool -FriendlyName AsHciDisk -ResiliencySettingName Simple -NumberOfColumns $diskNum -UseMaximumSize
        }
        TestScript = {
            (Get-VirtualDisk -ErrorAction SilentlyContinue -FriendlyName AsHciDisk).OperationalStatus -eq 'OK'
        }
        GetScript  = {
            @{Ensure = if ((Get-VirtualDisk -FriendlyName AsHciDisk).OperationalStatus -eq 'OK') { 'Present' } Else { 'Absent' } }
        }
        DependsOn  = "[Script]StoragePool"
    }
    Script FormatDisk {
        SetScript  = {
            $vDisk = Get-VirtualDisk -FriendlyName AsHciDisk
            if ($vDisk | Get-Disk | Where-Object PartitionStyle -eq 'raw') {
                $vDisk | Get-Disk | Initialize-Disk -Passthru | New-Partition -DriveLetter $Using:targetDrive -UseMaximumSize | Format-Volume -NewFileSystemLabel AsHciData -AllocationUnitSize 64KB -FileSystem NTFS
            }
            elseif ($vDisk | Get-Disk | Where-Object PartitionStyle -eq 'GPT') {
                $vDisk | Get-Disk | New-Partition -DriveLetter $Using:targetDrive -UseMaximumSize | Format-Volume -NewFileSystemLabel AsHciData -AllocationUnitSize 64KB -FileSystem NTFS
            }
        }
        TestScript = { 
            (Get-Volume -ErrorAction SilentlyContinue -FileSystemLabel AsHciData).FileSystem -eq 'NTFS'
        }
        GetScript  = {
            @{Ensure = if ((Get-Volume -FileSystemLabel AsHciData).FileSystem -eq 'NTFS') { 'Present' } Else { 'Absent' } }
        }
        DependsOn  = "[Script]VirtualDisk"
    }
    
    }
    
    
    
    }
    
    
    