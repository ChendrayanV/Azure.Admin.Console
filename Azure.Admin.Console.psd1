@{
    RootModule           = 'Azure.Admin.Console.psm1'
    ModuleVersion        = '0.10.0'
    GUID                 = '9923da59-cf92-4a4a-b855-f59a088a3f09'
    Author               = 'Chendrayan Venkatesan'
    CompanyName          = 'Golden Five Consulting'
    Copyright            = '(c) 2026 Chendrayan Venkatesan. Licensed under the MIT License.'
    Description          = 'Azure admin reports and checks from PowerShell, over plain REST - no Az or Microsoft.Graph modules, no app registration. Get-AACAdvisorRecommendation: a consolidated, flattened Azure Advisor view (Cost, Security, Reliability, Operational excellence, Performance) as a colour-coded console view, objects, CSV or PDF. Export-AACFirewallRule: every Azure Firewall Policy rule as objects, CSV or PDF. Invoke-AACPester: runs any Pester v5 tests with a live progress display, a rich report and optional PDF - by default the bundled Azure estate check, 85 read-only checks (75 following PSRule for Azure) across Storage, Key Vault, API Management, Application Gateway and WAF, Service Bus, Application Insights, Managed Grafana, Logic Apps, networking, backup and diagnostics. PDF export needs Windows and PowerShell 7.4+.'
    PowerShellVersion    = '7.2'
    CompatiblePSEditions = @('Core')

    # Pester is the only PowerShell module dependency. The console UI comes from
    # the vendored .\lib\Spectre.Console.dll (loaded directly via Add-Type in the
    # root module, MIT licensed, see .\lib\Spectre.Console.LICENSE), and Azure
    # access comes from plain REST calls (Invoke-RestMethod) against Azure
    # Resource Manager - no Az.* or Microsoft.Graph.* modules anywhere. PDF
    # reports use the vendored PDFsharp + MigraDoc assemblies in .\lib\pdf
    # (MIT, see lib\pdf\SOURCES.md), loaded only on export after a SHA-256
    # check of every file.
    RequiredModules      = @(
        @{ ModuleName = 'Pester'; ModuleVersion = '5.7.1' }
    )

    FunctionsToExport    = @(
        'Connect-AAC'
        'Disconnect-AAC'
        'Export-AACFirewallRule'
        'Export-AACPesterReport'
        'Get-AACAdvisorRecommendation'
        'Invoke-AACPester'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()

    PrivateData          = @{
        PSData = @{
            Tags         = @('Azure', 'AzureAdvisor', 'AzureFirewall', 'FirewallPolicy', 'ResourceGraph', 'Governance', 'Report', 'PDF', 'CSV', 'Pester', 'Testing', 'SpectreConsole', 'REST', 'PKCE', 'PSEdition_Core', 'Windows', 'Linux', 'MacOS')
            ProjectUri   = 'https://github.com/ChendrayanV/Azure.Admin.Console'
            LicenseUri   = 'https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/LICENSE'
            ReleaseNotes = 'v0.10.0: New Get-AACAdvisorRecommendation - a consolidated, flattened Azure Advisor view (Resource Graph advisorresources): a Spectre.Console summary at the prompt, objects when piped or with -PassThru/-NoDisplay, CSV (identical columns on every row, optional Ext_ column per extendedProperties key) and/or PDF, with estimated savings per currency, service retirement dates and postponed/dismissed status. Invoke-AACPester now defaults to the bundled Checks folder (the live Azure estate check). Per-cmdlet help in docs\ and an about_Azure.Admin.Console topic. First PowerShell Gallery release. Full history: CHANGELOG.md.'
        }
    }
}
