Configuration ASHCIHost {
Param()


Import-DscResource -ModuleName "PSDesiredStateConfiguration"

Node 'localhost'{
        WindowsFeature Hyper-V {
        Name = "Hyper-V" 
        Ensure = "Present"
        }
    }



}