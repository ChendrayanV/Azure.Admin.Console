function Invoke-AACPSRule {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Checks your live Azure estate with PSRule for Azure - its Azure
        Well-Architected Framework rules, the module's own rules and your
        custom rules - with a console view, objects, and CSV, PDF and
        interactive HTML reports.
    .DESCRIPTION
        Runs PSRule for Azure (the PSRule.Rules.Azure module, 500+ rules)
        against every resource, resource group and subscription the
        signed-in account can see, or those in -SubscriptionId. No Az modules:
        the data PSRule needs - what Export-AzRuleData would export - is read
        with the Connect-AAC sign-in, from Azure Resource Graph plus the child
        settings PSRule's rules look at (storage blob services, SQL auditing,
        Key Vault diagnostic settings, App Service config, API Management
        APIs and policies, ...). Reader on the subscriptions is enough.

        The rules that run:
          PSRule for Azure    every rule of the installed PSRule.Rules.Azure
                              (-Baseline picks one of its baselines)
          Azure.Admin.Console the module's own AAC.* rules (PSRule\Rules):
                              required tags on resources and resource
                              groups and allowed tag values - the tags
                              named in -Configuration or in
                              Get-AACTagDefault (PSRule\Rules\AAC.Tags.Rule.ps1);
                              with none named they check nothing, and the
                              view says so - and naming conventions (on by default: the
                              Cloud Adoption Framework abbreviations, or
                              AAC_NAMING_PATTERNS)
          custom              your own PSRule rule files (*.Rule.ps1,
                              *.Rule.yaml, *.Rule.jsonc) from -RulePath
        -Rule runs only the rules named, and -ExcludeRule leaves rules out;
        both take names or wildcards ('Azure.Storage.*', 'AAC.*').
        -Configuration passes settings to all of them: PSRule for Azure's
        AZURE_* options and the AAC_* settings.

        What you get depends on where the command runs:
          at the prompt    a Spectre.Console view: tiles (objects, rules,
                           passed, failed, pass rate), failures by pillar,
                           then a table per pillar with each failing rule,
                           the resources it failed on and why - a page at a
                           time (-NoPaging turns that off)
          piped onward     the AAC.PSRuleResult objects, with no view
          -PassThru        the view and the objects
          -NoDisplay       the objects only

        Exports:
          -CsvPath    one row per rule and resource (-FailedOnly: failures
                      only)
          -PdfPath    a landscape A4 report: summary and verdict, results
                      by pillar, the failed rules, then every failing
                      resource per rule with the rule's recommendation and
                      documentation link
          -HtmlPath   a self-contained, interactive HTML report: clickable
                      tiles and charts, and every result in one table that
                      opens on the failures, grouped by rule, with search,
                      filters, portal and documentation links and a CSV
                      download
        When any of them is given, the console shows only the progress and
        the files written; add -PassThru for the objects too.

        PSRule runs in a pwsh process of its own, so its YamlDotNet.dll
        never meets the different versions platyPS, powershell-yaml or Az.Aks
        may have loaded in this session. A rule that can't evaluate a
        resource is reported for that resource ("could not evaluate");
        every other rule still runs. Settings Reader can't read are listed
        as warnings, as rules using them may be wrong for those resources.
    .PARAMETER SubscriptionId
        Only check these subscriptions. Defaults to every subscription the
        signed-in account can see.
    .PARAMETER ResourceType
        Only check resources of these types, e.g. 'microsoft.storage/*'.
        Case-insensitive; wildcards work. Resource groups and subscriptions
        are checked only when no type is given.
    .PARAMETER Rule
        Only run these rules: names or wildcards, e.g. 'Azure.KeyVault.*' or
        'AAC.Resource.Naming' - not file paths (use -RulePath for rule
        files). A -Rule that matches no rule is an error. With only the
        module's AAC.* rules, just names, types and tags are read - and for
        AAC.Resource.Naming alone, just the types it checks.
    .PARAMETER ExcludeRule
        Leave out these rules: names or wildcards, e.g. 'Azure.Resource.UseTags'
        or 'AAC.*'.
    .PARAMETER Baseline
        A PSRule for Azure baseline, e.g. 'Azure.Pillar.Security' or
        'Azure.GA_2024_12'. Defaults to the module's default baseline.
    .PARAMETER Configuration
        Settings for the rules: PSRule for Azure's options (e.g.
        AZURE_RESOURCE_ALLOWED_LOCATIONS) and the AAC_* settings of the
        module's rules (AAC_REQUIRED_TAGS, AAC_ALLOWED_TAG_VALUES), or your
        custom rules' own.
    .PARAMETER RulePath
        Custom PSRule rule files, or folders of them (*.Rule.ps1,
        *.Rule.yaml, *.Rule.jsonc), to run with the others. The module's own
        AAC.* rules always load; don't pass them here.
    .PARAMETER NoExpand
        Read only what Resource Graph returns - names, types, tags and
        properties - not the child settings PSRule for Azure's rules need
        (diagnostic settings, blob services, API Management APIs, ...: one
        to hundreds of calls per resource). For your own -RulePath rules
        that look only at those fields. Runs of only the module's AAC.*
        rules do this without asking.
    .PARAMETER FailedOnly
        Return and export only the failures (and rules that couldn't be
        evaluated). The counts still cover every result.
    .PARAMETER CsvPath
        Also write the results to this CSV file. An existing file is
        overwritten; missing folders are created.
    .PARAMETER PdfPath
        Also write a PDF report to this file. Needs Windows and PowerShell
        7.4 or later.
    .PARAMETER HtmlPath
        Also write an interactive HTML report to this file.
    .PARAMETER Title
        The PDF and HTML report's title. Defaults to 'PSRule for Azure'.
    .PARAMETER PassThru
        Show the view and also return the AAC.PSRuleResult objects.
    .PARAMETER NoDisplay
        Return the objects without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once instead of a page at a time.
    .EXAMPLE
        Connect-AAC
        Invoke-AACPSRule
        Checks every resource you can see and shows what failed.
    .EXAMPLE
        Invoke-AACPSRule -SubscriptionId '00000000-0000-0000-0000-000000000000' -HtmlPath .\out\PSRule.html
        One subscription, as an interactive HTML report.
    .EXAMPLE
        Invoke-AACPSRule -CsvPath .\out\PSRule.csv -PdfPath .\out\PSRule.pdf -FailedOnly
        The failures as a CSV file and a PDF report.
    .EXAMPLE
        Invoke-AACPSRule -Rule 'Azure.Storage.*', 'Azure.KeyVault.*' -ExcludeRule 'Azure.Storage.Name'
        Only the storage and Key Vault rules, without the storage naming rule.
    .EXAMPLE
        Invoke-AACPSRule -Baseline 'Azure.Pillar.Security'
        Only PSRule for Azure's security pillar baseline.
    .EXAMPLE
        Invoke-AACPSRule -Configuration @{ AAC_REQUIRED_TAGS = @('Owner', 'CostCenter'); AAC_ALLOWED_TAG_VALUES = @{ Environment = @('prod', 'test', 'dev') }; AZURE_RESOURCE_ALLOWED_LOCATIONS = @('uksouth', 'ukwest') }
        Adds the module's tag rules and PSRule for Azure's allowed regions.
    .EXAMPLE
        Invoke-AACPSRule -Rule 'AAC.Resource.Naming'
        Checks names against the Cloud Adoption Framework abbreviations, reading only the types it checks.
    .EXAMPLE
        Invoke-AACPSRule -RulePath .\MyRules -ExcludeRule 'AAC.*'
        Runs your own rules from .\MyRules with PSRule for Azure's, without the module's.
    .EXAMPLE
        Invoke-AACPSRule -FailedOnly | Group-Object RuleName | Sort-Object Count -Descending | Select-Object -First 10 Count, Name
        The ten rules that fail most.
    .OUTPUTS
        AAC.PSRuleResult (piped onward, or with -PassThru or -NoDisplay)
    #>
    [CmdletBinding()]
    [OutputType('AAC.PSRuleResult')]
    param(
        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [SupportsWildcards()]
        [string[]] $ResourceType,

        [SupportsWildcards()]
        [string[]] $Rule,

        [SupportsWildcards()]
        [string[]] $ExcludeRule,

        [string] $Baseline,

        [hashtable] $Configuration = @{},

        [string[]] $RulePath,

        [switch] $NoExpand,

        [switch] $FailedOnly,

        [string] $CsvPath,

        [string] $PdfPath,

        [string] $HtmlPath,

        [string] $Title = 'PSRule for Azure',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    # A failure anywhere below ends as a Spectre.Console error panel and this
    # command's own terminating error, not a line inside the module. A stopped
    # pipeline (Select-Object -First, Ctrl+C) is no failure: just return - a
    # rethrow would stop the caller's whole script, not only this command.
    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    # An export means the report is in the files: the console shows only the
    # title, the progress and the files written.
    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $exporting = [bool]($CsvPath -or $PdfPath -or $HtmlPath)
    $showView = $interactive -and -not $exporting
    $returnObjects = $PassThru -or $NoDisplay -or $pipedOnward

    # Resolve paths now, relative to the caller's location, so a bad path
    # fails before any Azure call.
    $resolve = { param([string] $Path) if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } }
    $csvFullPath = & $resolve $CsvPath
    $pdfFullPath = & $resolve $PdfPath
    $htmlFullPath = & $resolve $HtmlPath
    $rulePaths = @(foreach ($path in @($RulePath | Where-Object { $_ })) {
            $full = & $resolve $path
            if (-not (Test-Path -LiteralPath $full)) { throw "The rule path '$path' does not exist." }
            $full
        })

    # What the rules need read - and a -Rule that can't match anything -
    # worked out before any Azure call.
    $plan = Get-AACPSRulePlan -Rule @($Rule | Where-Object { $_ }) -ExcludeRule @($ExcludeRule | Where-Object { $_ }) -RulePath $rulePaths -Baseline $Baseline -ResourceType @($ResourceType | Where-Object { $_ }) -Configuration $Configuration -NoExpand:$NoExpand

    # Fails with a clear message before anything is drawn.
    $null = Get-AACAccessToken

    if ($interactive) {
        Write-AACRule -Title 'Azure Admin Console :: PSRule for Azure' -Color 'deepskyblue3_1'
    }
    $run = Invoke-AACProgress -ScriptBlock {
        $engine = @{
            SubscriptionId = @($SubscriptionId | Where-Object { $_ })
            ResourceType   = @($plan.ResourceType)
            NoExpand       = -not $plan.Expand
            Rule           = @($Rule | Where-Object { $_ })
            ExcludeRule    = @($ExcludeRule | Where-Object { $_ })
            Baseline       = $Baseline
            Configuration  = $Configuration
            RulePath       = $rulePaths
        }
        Invoke-AACPSRuleEngine @engine
    }
    $results = @($run.Results)
    if ($Rule -and $run.Rules -eq 0) {
        throw "No rule matches -Rule $(($Rule | ForEach-Object { "'$_'" }) -join ', ')$(if ($ExcludeRule) { " (after -ExcludeRule)" }). Use rule names or wildcards: 'AAC.*' for the module's rules, 'Azure.Storage.*' for PSRule for Azure's - or run without -Rule to list them all."
    }
    $listed = if ($FailedOnly) { @($results | Where-Object Outcome -NE 'Pass') } else { $results }

    # What was checked, for the view and the reports.
    $scope = [ordered]@{
        Subscriptions = if ($SubscriptionId) { $SubscriptionId -join ', ' } else { 'every subscription the account can see' }
    }
    if ($ResourceType) { $scope['Resource types'] = $ResourceType -join ', ' }
    if ($Rule) { $scope['Rules'] = $Rule -join ', ' }
    if ($ExcludeRule) { $scope['Excluded rules'] = $ExcludeRule -join ', ' }
    if ($Baseline) { $scope['Baseline'] = $Baseline }
    if ($RulePath) { $scope['Custom rules'] = $RulePath -join ', ' }
    if ($plan.Read) { $scope['Read'] = $plan.Read }
    if ($Configuration.Count) {
        $scope['Settings'] = (@($Configuration.Keys | Sort-Object | ForEach-Object {
                    $value = $Configuration[$_]
                    $text = if ($value -is [System.Collections.IDictionary]) { '{' + (@($value.Keys | Sort-Object | ForEach-Object { "$_ = $(@($value[$_]) -join ', ')" }) -join '; ') + '}' } else { @($value) -join ', ' }
                    "$_ = $text"
                }) -join '; ')
    }
    $scope['PSRule for Azure'] = $run.Version

    foreach ($warning in @($plan.Notice) + @($run.Warnings)) {
        if ($warning -and -not $showView) { Write-Warning $warning }
    }

    $null = Invoke-AACExport -CsvPath $csvFullPath -CsvObject $listed -Noun 'result' -PdfPath $pdfFullPath -WritePdf {
        Write-AACPSRulePdf -Result $results -Path $pdfFullPath -Title $Title -Detail $scope -Rules $run.Rules -Objects $run.Objects
    } -HtmlPath $htmlFullPath -WriteHtml {
        Write-AACPSRuleHtml -Result $results -Path $htmlFullPath -Title $Title -Detail $scope -Rules $run.Rules -Objects $run.Objects -Warning (@($plan.Notice) + @($run.Warnings) | Where-Object { $_ }) -FailedOnly:$FailedOnly
    }

    if ($showView) {
        Invoke-AACPagedOutput -NoPaging:$NoPaging -ScriptBlock {
            Show-AACPSRuleView -Result $results -Scope $scope -Rules $run.Rules -Objects $run.Objects -Warning $run.Warnings -Notice $plan.Notice
            Write-AACMarkup '[grey42]Add -PassThru (or pipe the command) for the objects; -CsvPath, -PdfPath or -HtmlPath for a report.[/]'
        }
    }

    if ($returnObjects) {
        $listed
    }
}
