@{
    ModuleVersion = '1.0'
    Author = 'Romero126'
    CompanyName = 'n/a'
    Copyright = '(c) 2024 Romero126. All rights reserved.'
    Description = 'CoreAdmin is a management database tool designed to integrate with CoreAdmin tools to help orchestrate deployment'
    RootModule = "CoreAdmin.psm1"
    #FileList = @(
    #    'CoreAdmin.psm1'
    #)
    PrivateData = @{
        DatabasePath = "$PSScriptRoot\..\..\Database\"
        #Schema_Type = @([System.Type][System.String], [System.Type][System.Guid], [System.Int32], [System.Boolean], [System.Byte[]])

        PSData = @{
            # Tags = @()
            # LicenseUri = ''
            # ProjectUri = ''
            # IconUri = ''
            # ReleaseNotes = ''
            Value = "asdf"
        } # End of PSData hashtable
    } # End of PrivateData hashtable

}