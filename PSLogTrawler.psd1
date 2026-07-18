@{
    RootModule        = 'PSLogTrawler.psm1'
    ModuleVersion     = '0.1.0'
    GUID              = 'b3f4c6e2-1a7d-4f8b-9c2e-6d5a0e4b1c37'
    Author            = 'Michael Tarassov'
    CompanyName       = 'Michael Tarassov'
    Copyright         = '(c) 2021 Michael Tarassov. MIT License.'
    Description       = 'Cross-platform toolkit for parsing and analyzing plain-text log files.'
    PowerShellVersion = '7.1'

    FormatsToProcess  = @('PSLogTrawler.Format.ps1xml')

    FunctionsToExport = @(
        'ConvertFrom-LogLine',
        'Get-LogSummary',
        'Select-LogError',
        'Measure-LogRate'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData = @{
        PSData = @{
            Tags       = @('logging', 'log', 'parsing', 'analysis', 'devops', 'crossplatform')
            LicenseUri = 'https://opensource.org/licenses/MIT'
            ProjectUri = 'https://github.com/cybercapybara/pslogtrawler'
            ReleaseNotes = 'Initial 0.1.0 release: ConvertFrom-LogLine, Get-LogSummary, Select-LogError, Measure-LogRate.'
        }
    }
}
