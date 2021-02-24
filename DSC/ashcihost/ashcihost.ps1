Configuration Hypervisor {

    Import-DscResource -ModuleName 'PSDesiredStateConfiguration'
    
    Node Hypervisor{
    
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
    
    
    }
    
    
    
    }
    
    Hypervisor 
    
    
    