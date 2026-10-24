function Invoke-AACWafAssessment {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Assesses the estate against the Azure Well-Architected Framework's
        five pillars - Reliability, Security, Cost Optimization, Operational
        Excellence and Performance Efficiency - scored by pillar, design
        principle and check, with workbook-style heat maps by subscription, resource group
        or resource type, findings and what to do, a Spectre.Console view,
        objects, and CSV, PDF and interactive HTML reports.
    .DESCRIPTION
        Read-only, with one batch of Azure Resource Graph queries - Reader is
        enough, no Az modules. Every check is evaluated against that one read:
          the resources the checks test (VMs, scale sets, disks, snapshots,
          storage, SQL, App Service, Key Vault, AKS, load balancers,
          Application Gateways, public IPs, NSGs, NICs, Cosmos DB, Redis,
          container registries, Recovery Services vaults, virtual networks,
          resource groups), VM extensions, autoscale settings, deployment
          slots, what Azure Backup protects, how many alert rules and action
          groups each subscription has, Azure Advisor's recommendations in
          the pillars' categories, and Defender for Cloud's plans, secure
          scores and high-severity assessments.

        Each pillar is scored against its design principles (Microsoft
        Learn):
          Reliability  business requirements, resilience, recovery,
                       operations, simplicity - zones, backups, redundancy,
                       instance counts, retired Basic SKUs, health probes, SLA
                       tiers
          Security     security readiness, confidentiality, integrity,
                       availability, sustained posture - Defender plans and
                       secure score, TLS, HTTPS, public access, network
                       restrictions, keys and local accounts, management ports
                       open to the internet, WAF, DDoS
          Cost         cost-management discipline, cost-efficiency, usage and
                       rate optimization, monitoring - cost-allocation tags
                       (-CostTag), unattached disks, unused public IPs, VMs
                       stopped but billed, empty plans, old snapshots, Azure
                       Hybrid Benefit, old VM generations
          Operational  DevOps culture, standards, observability, deployment,
          Excellence   automation - owner and environment tags (-OwnerTag),
                       the Azure Monitor agent, boot diagnostics, Application
                       Insights, alert rules and action groups, deployment
                       slots, platform patching, AKS auto-upgrade
          Performance  targets, capacity, sustained performance, optimization
          Efficiency   - autoscale on plans, scale sets, AKS and Application
                       Gateway, accelerated networking, SSD OS disks, SQL and
                       Redis tiers
        Advisor and Defender are checks too, one per pillar (AD-HA, AD-SEC,
        AD-COST, AD-OPS, AD-PERF, DF-HIGH): a resource with an open
        recommendation fails. An item that is the same finding as a catalogue
        check on the same resource is counted once, by the catalogue check,
        whose result says 'Also flagged by Advisor' (or Defender);
        -KeepDuplicates counts both.

        What no API can test - business requirements, threat models, budgets,
        performance targets, team practices - comes from the questionnaire:
        Export-AACWafQuestionnaire writes one question per principle, the team
        answers Yes, Partly or No, and -AttestationPath scores the answers
        (checks AT-..., heat-map column 'Attested'). -HistoryPath keeps a line
        per run and shows the change since the last one.

        Scores are out of 100: a check's is the share of resources that pass;
        a principle's and a pillar's weigh their checks by severity (High 3,
        Medium 2, Low 1). A principle no check covers is shown as not
        assessed: it needs a review or attestation. Each pillar gets a
        maturity: Initial (under 50), Developing, Established (75+),
        Optimised (90+).

        The heat maps - pillars, and design principles, by -HeatMapBy - show
        each cell's score in colour: at the prompt (the first eight columns),
        in the PDF (ten columns a table) and in the HTML report, where
        clicking a cell lists its findings.

        What you get depends on where the command runs:
          at the prompt    tiles, the heat maps, the principles, and the top
                           findings - a page at a time
          piped onward     one AAC.WafCheckResult per check and resource
          -PassThru        the view and the results
          -NoDisplay       the results only
        -CsvPath writes every result; -HtmlPath an interactive report
        (summary with heat maps, principles, checks, findings); -PdfPath a PDF.
    .PARAMETER SubscriptionId
        Only these subscriptions.
    .PARAMETER ManagementGroupId
        Only the subscriptions under these management groups.
    .PARAMETER ResourceGroupName
        Only these resource groups (a workload).
    .PARAMETER Pillar
        The pillars to assess (all five by default): Reliability, Security,
        'Cost Optimization', 'Operational Excellence', 'Performance
        Efficiency'.
    .PARAMETER HeatMapBy
        The heat maps' columns: Subscription (the default), ResourceGroup or
        ResourceType.
    .PARAMETER ExcludeCheck
        Check IDs to leave out; wildcards work: 'SE-24', 'AD-*', 'DF-*'.
    .PARAMETER NoAdvisor
        Leave out Azure Advisor's recommendations.
    .PARAMETER NoDefender
        Leave out Defender for Cloud: plans, secure score and assessments.
    .PARAMETER AttestationPath
        An answered questionnaire (Export-AACWafQuestionnaire) to score with
        the automated checks.
    .PARAMETER HistoryPath
        A CSV file that keeps a line per run - overall and pillar scores - for
        the trend.
    .PARAMETER KeepDuplicates
        Count an Advisor or Defender item even when a catalogue check already
        tested the same thing on the same resource.
    .PARAMETER CostTag
        The tag names that allocate cost (any one counts).
    .PARAMETER OwnerTag
        The tag names that name an owner (any one counts).
    .PARAMETER CsvPath
        Write every result to this CSV file.
    .PARAMETER HtmlPath
        Write an interactive HTML report.
    .PARAMETER PdfPath
        Write a PDF report.
    .PARAMETER Title
        The reports' title.
    .PARAMETER PassThru
        Show the view and also return the results.
    .PARAMETER NoDisplay
        Return the results without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once.
    .EXAMPLE
        Connect-AAC
        Invoke-AACWafAssessment
        All five pillars across every subscription, with heat maps by subscription.
    .EXAMPLE
        Export-AACWafQuestionnaire -Path .\waf-answers.csv
        Invoke-AACWafAssessment -ResourceGroupName 'rg-app-prod' -AttestationPath .\waf-answers.csv -HistoryPath .\waf-history.csv -HtmlPath .\out\WAF.html
        A workload's review with the team's answers, and its trend from run to run.
    .EXAMPLE
        Invoke-AACWafAssessment -ResourceGroupName 'rg-app-prod' -HeatMapBy ResourceType -HtmlPath .\out\WAF.html -PdfPath .\out\WAF.pdf
        One workload's go-live review, as HTML and PDF reports.
    .EXAMPLE
        Invoke-AACWafAssessment -ManagementGroupId 'mg-landingzones' -Pillar Reliability -HeatMapBy ResourceGroup
        The landing zones' reliability, resource group by resource group.
    .EXAMPLE
        Invoke-AACWafAssessment -NoDisplay | Where-Object { $_.Status -eq 'Fail' -and $_.Severity -eq 'High' } | Group-Object Check
        The high-severity gaps, by check.
    .OUTPUTS
        AAC.WafCheckResult (piped onward, or with -PassThru or -NoDisplay)
    #>
    [CmdletBinding()]
    [OutputType('AAC.WafCheckResult')]
    param(
        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [ValidateNotNullOrEmpty()]
        [string[]] $ManagementGroupId,

        [ValidateNotNullOrEmpty()]
        [string[]] $ResourceGroupName,

        [ValidateSet('Reliability', 'Security', 'Cost Optimization', 'Operational Excellence', 'Performance Efficiency')]
        [string[]] $Pillar = @('Reliability', 'Security', 'Cost Optimization', 'Operational Excellence', 'Performance Efficiency'),

        [ValidateSet('Subscription', 'ResourceGroup', 'ResourceType')]
        [string] $HeatMapBy = 'Subscription',

        [SupportsWildcards()]
        [string[]] $ExcludeCheck,

        [switch] $NoAdvisor,

        [switch] $NoDefender,

        [string] $AttestationPath,

        [string] $HistoryPath,

        [switch] $KeepDuplicates,

        [ValidateNotNullOrEmpty()]
        [string[]] $CostTag = @('CostCenter', 'CostCentre', 'Cost Center', 'Project', 'Application', 'BillingCode'),

        [ValidateNotNullOrEmpty()]
        [string[]] $OwnerTag = @('Owner', 'Contact', 'TechnicalOwner', 'BusinessOwner'),

        [string] $CsvPath,

        [string] $HtmlPath,

        [string] $PdfPath,

        [string] $Title = 'Well-Architected assessment',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $resolve = { param([string] $Path) if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } }
    $request = @{
        SubscriptionId = @($SubscriptionId | Where-Object { $_ }); ManagementGroupId = @($ManagementGroupId | Where-Object { $_ }); ResourceGroupName = @($ResourceGroupName | Where-Object { $_ })
        Pillar = @($Pillar | Select-Object -Unique); HeatMapBy = $HeatMapBy; ExcludeCheck = @($ExcludeCheck | Where-Object { $_ }); NoAdvisor = [bool]$NoAdvisor; NoDefender = [bool]$NoDefender
        AttestationPath = & $resolve $AttestationPath; HistoryPath = & $resolve $HistoryPath; CostTag = @($CostTag); OwnerTag = @($OwnerTag); KeepDuplicates = [bool]$KeepDuplicates
    }

    $null = Get-AACAccessToken
    if ($interactive) { Write-AACRule -Title 'Azure Admin Console :: Well-Architected assessment' -Color 'mediumpurple2' }
    $state = Get-AACWafAssessment -Request $request
    $history = if ($request.HistoryPath) { Write-AACWafHistory -Path $request.HistoryPath -State $state }
    $report = ConvertTo-AACWafReport -State $state -Request $request -History $history
    $result = $state.Result
    Invoke-AACReportOutput -Report $report -Title $Title -CsvObject @($result.Results) -Noun 'result' -CsvPath (& $resolve $CsvPath) -HtmlPath (& $resolve $HtmlPath) -PdfPath (& $resolve $PdfPath) `
        -ShowView:$interactive -NoPaging:$NoPaging -Object @($result.Results) -ReturnObject:($PassThru -or $NoDisplay -or $pipedOnward)
}
