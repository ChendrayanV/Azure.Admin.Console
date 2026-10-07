function Write-AACDefenderAssessmentCsv {
    <#
    .SYNOPSIS
        Writes Invoke-AACDefenderAssessment's tables to CSV files in a folder,
        and returns the files.
    .DESCRIPTION
        findings, recommendations, unhealthy-resources, attack-paths, alerts,
        suppression-rules, inventory, vulnerabilities, subscriptions,
        secure-score-controls, plans, connectors, compliance-standards,
        compliance-controls, compliance-assessments, settings and
        jit-policies - each prefixed defender-. Empty tables are left out.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Assessment,

        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
    $files = [ordered]@{
        findings = 'Findings'; recommendations = 'Recommendations'; 'unhealthy-resources' = 'UnhealthyResources'; 'attack-paths' = 'AttackPaths'
        alerts = 'Alerts'; 'suppression-rules' = 'SuppressionRules'; inventory = 'Inventory'; vulnerabilities = 'Vulnerabilities'; subscriptions = 'Subscriptions'
        'secure-score-controls' = 'Controls'; plans = 'Plans'; connectors = 'Connectors'; 'compliance-standards' = 'Standards'
        'compliance-controls' = 'ComplianceControls'; 'compliance-assessments' = 'ComplianceAssessments'; settings = 'Settings'; 'jit-policies' = 'JitPolicies'
    }
    foreach ($file in $files.Keys) {
        $rows = @($Assessment[$files[$file]])
        if (-not $rows.Count) { continue }
        $target = Join-Path -Path $Path -ChildPath "defender-$file.csv"
        $rows | Export-Csv -LiteralPath $target -NoTypeInformation -Encoding utf8
        Get-Item -LiteralPath $target
    }
}
