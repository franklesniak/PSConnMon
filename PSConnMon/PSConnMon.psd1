@{
    RootModule = 'PSConnMon.psm1'
    ModuleVersion = '0.2.0'
    GUID = 'c67d6a0a-3411-4b40-89ff-06c4afdd7f7e'
    Author = 'Frank Lesniak'
    CompanyName = 'Community'
    Copyright = '(c) 2025-2026 Frank Lesniak'
    Description = 'PowerShell connectivity monitoring module for PSConnMon.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'ConvertTo-PSConnMonConfig',
        'Export-PSConnMonSampleConfig',
        'Invoke-PSConnMon',
        'Start-PSConnMonCycle',
        'Test-PSConnMonConfig',
        'Test-PSConnMonDnsQuery',
        'Test-PSConnMonDomainAuth',
        'Test-PSConnMonInternetQuality',
        'Test-PSConnMonPing',
        'Test-PSConnMonShare',
        'Test-PSConnMonTraceroute',
        'Write-PSConnMonEvent'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('PSConnMon', 'Monitoring', 'Connectivity', 'PowerShell')
            ProjectUri = 'https://github.com/franklesniak/PSConnMon'
            LicenseUri = 'https://opensource.org/licenses/MIT'
        }
    }
}
