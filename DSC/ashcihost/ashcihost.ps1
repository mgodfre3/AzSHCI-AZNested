Configuration ASHCIHost {

    param(
    [Parameter(Mandatory)]
    [System.Management.Automation.PSCredential]$Admincreds,
    [String]$targetDrive = "V",
    [String]$targetVMPath = "$targetDrive" + ":\VMs",
    [String]$OSDrive = "C",
    [String]$ScriptPath = "$OSDrive" + ":\AzHCIVHDs",
    [String]$dsc_source="https://raw.githubusercontent.com/billcurtis/AzSHCISandbox/main/",
    [Parameter(Mandatory)]
    [string]$customRdpPort
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
    
    #Required Folders for ASHCI Deployment
    


    File "VMfolder" {
        Type            = 'Directory'
        DestinationPath = "$targetVMPath"
        DependsOn       = "[Script]FormatDisk"
        
    }

    File "ASHCIBuildScripts" {
        Type            = 'Directory'
        DestinationPath = "$ScriptPath"
        DependsOn       = "[Script]FormatDisk"
    }

    xRemoteFile "VHDs_Server2019" {
        DestinationPath=$ScriptPath
        URI="https://ashcinested.blob.core.windows.net/vhd/Server2019DC.vhdx?sp=r&st=2021-02-24T20:35:08Z&se=2021-04-01T03:35:08Z&spr=https&sv=2020-02-10&sr=b&sig=ULLmTD5VI0gcFtCApmiebQm%2Fm%2FgVSFR3eZZpn4tBBSI%3D"
    }

    xRemoteFile "VHDs_ASHCI" {
        DestinationPath=$ScriptPath
        URI="https://ashcinested.blob.core.windows.net/vhd/AzStackHCIPreview1.vhdx?sp=r&st=2021-02-24T20:50:45Z&se=2021-04-01T03:50:45Z&spr=https&sv=2020-02-10&sr=b&sig=ZKkxiEZtvnaPUCmzrov3corWnc6jeYZMPSU0pV4eeoo%3D"
    }

    xRemoteFile "BuildScripts" {
        DestinationPath="$ScriptPath"
        URI="$dsc_source"
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
    
    