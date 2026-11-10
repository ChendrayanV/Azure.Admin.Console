function Get-AACSecurityPosture {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Deprecated: use Invoke-AACDefenderAssessment -View Posture.
        Your security posture in one place - Microsoft Defender for Cloud's
        secure scores, recommendations by control, active alerts, Defender
        plans and regulatory compliance, and Azure Policy compliance -
        flattened to one list of findings,
        with a Spectre.Console view, objects, and CSV, PDF and interactive
        HTML reports.
    .DESCRIPTION
        Deprecated, and to be removed in a later release: Invoke-AACDefenderAssessment
        -View Posture gives the same, with the same parameters. This command still
        works, and warns.

        Reads Defender for Cloud with Azure Resource Graph (securityresources;
        Reader or Security Reader is enough, no Az modules) - every query at
        once. -Section picks what to read (all of them by default):
          Score            each subscription's secure score (Defender's own
                           points, added up across subscriptions as Defender
                           does) and the secure score controls, with the
                           potential increase of fixing each
          Recommendations  every unhealthy recommendation on each resource:
                           severity, the control it belongs to, category,
                           description, remediation steps and its portal page
          Alerts           active and in-progress security alerts: severity,
                           intent, resource, how old, and the alert's page
          Plans            which Defender plans are on or off per subscription
          Compliance       each regulatory standard's passed and failed
                           controls, and for a failed control the resources
                           failing the recommendations behind it
          Policy           Azure Policy: each assignment's compliance rate
                           (compliant / compliant + non-compliant
                           resources), and every non-compliant resource with
                           the policy and its effect

        -ResourceGroupName and -Tag narrow the recommendations, alerts and
        compliance failures to those resources (tag values are matched
        exactly, ignoring case); scores, plans and standards are per
        subscription. -Standard picks compliance standards by name.

        One row per finding (AAC.SecurityFinding), the same in the objects,
        CSV, HTML and PDF: Section (Recommendation, Alert, Compliance, Policy
        or Plan), Severity (none for Policy), Title, Category, Control, Resource, Type,
        ResourceGroup, SubscriptionName, State, Detail, Link (the Azure
        portal page), Since and ResourceId - most severe first.

        The resource tree with each node's score and findings is
        Get-AACInventory's; this command is the posture itself.

        What you get depends on where the command runs:
          at the prompt    tiles, the subscriptions (score, findings, alerts,
                           plans), the recommendations grouped by
                           recommendation with every resource, the alerts,
                           compliance by standard with the failed controls,
                           and the plans that are off - a page at a time
          piped onward     the findings, with no view
          -PassThru        the view and the findings
          -NoDisplay       the findings only
        -CsvPath writes the findings. -HtmlPath writes an interactive report:
        tiles and charts that filter the tables - findings, subscriptions,
        secure score controls, compliance standards and controls, Defender
        plans - each searchable, with portal links and a CSV download.
        -PdfPath writes the same as a PDF.
    .PARAMETER SubscriptionId
        Only these subscriptions. Defaults to every subscription the account
        can see.
    .PARAMETER ResourceGroupName
        Only the recommendations, alerts and compliance failures on resources
        in these resource groups.
    .PARAMETER Tag
        Only the recommendations, alerts and compliance failures on resources
        with these tags, e.g. @{ Environment = 'Prod' } (all must match).
    .PARAMETER Section
        What to read: Score, Recommendations, Alerts, Plans, Compliance,
        Policy. All of them by default.
    .PARAMETER Standard
        Only these regulatory compliance standards (names or wildcards, e.g.
        'Microsoft-cloud-security-benchmark' or '*ISO*').
    .PARAMETER CsvPath
        Write every finding to this CSV file.
    .PARAMETER PdfPath
        Write a PDF report to this file.
    .PARAMETER HtmlPath
        Write an interactive HTML report to this file.
    .PARAMETER Title
        The PDF and HTML reports' title.
    .PARAMETER PassThru
        Show the view and also return the findings.
    .PARAMETER NoDisplay
        Return the findings without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once instead of a page at a time.
    .EXAMPLE
        Connect-AAC
        Get-AACSecurityPosture
        Every subscription's secure score, recommendations, alerts, plans and compliance.
    .EXAMPLE
        Get-AACSecurityPosture -Tag @{ Environment = 'Prod' } -HtmlPath .\out\Security.html
        The production resources' findings as an interactive HTML report.
    .EXAMPLE
        Get-AACSecurityPosture -Section Alerts, Plans
        Only the active alerts and the Defender plans.
    .EXAMPLE
        Get-AACSecurityPosture -Section Compliance -Standard '*ISO*' -PdfPath .\out\ISO.pdf
        ISO 27001 compliance, with the failing resources, as a PDF.
    .EXAMPLE
        Get-AACSecurityPosture -Section Policy -NoDisplay | Group-Object Category | Sort-Object Count -Descending
        The Azure Policy assignments with the most non-compliant resources.
    .EXAMPLE
        Get-AACSecurityPosture -NoDisplay | Where-Object { $_.Section -eq 'Recommendation' -and $_.Severity -eq 'High' } | Group-Object Title
        The High recommendations, and how many resources each is on.
    .OUTPUTS
        AAC.SecurityFinding (piped onward, or with -PassThru or -NoDisplay)
    #>
    [CmdletBinding()]
    [OutputType('AAC.SecurityFinding')]
    param(
        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [ValidateNotNullOrEmpty()]
        [string[]] $ResourceGroupName,

        [hashtable] $Tag,

        [ValidateSet('Score', 'Recommendations', 'Alerts', 'Plans', 'Compliance', 'Policy')]
        [string[]] $Section = @('Score', 'Recommendations', 'Alerts', 'Plans', 'Compliance', 'Policy'),

        [SupportsWildcards()]
        [string[]] $Standard,

        [string] $CsvPath,

        [string] $PdfPath,

        [string] $HtmlPath,

        [string] $Title = 'Security posture',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    # A failure anywhere below ends as a Spectre.Console error panel and this
    # command's own terminating error, not a line inside the module. A stopped
    # pipeline (Select-Object -First, Ctrl+C) is no failure: just return - a
    # rethrow would stop the caller's whole script, not only this command.
    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    Write-Warning 'Get-AACSecurityPosture is deprecated and will be removed in a later release. Use Invoke-AACDefenderAssessment -View Posture, with the same parameters.'
    Invoke-AACSecurityPostureReport @PSBoundParameters -OutputPiped:$pipedOnward
}