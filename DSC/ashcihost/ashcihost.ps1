Configuration ASHCIHost001 {

    Import-DscResource -ModuleName 'PSDesiredStateConfiguration'
    
    Node localhost{
    
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
    
    
    