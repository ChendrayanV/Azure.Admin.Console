function ConvertTo-AACSentinelRuleExport {
    <#
    .SYNOPSIS
        Turns Microsoft Sentinel analytics and automation rules, as Resource
        Manager returns them, into the JSON files Export-AACSentinelAnalyticsRule
        writes: one per rule.
    .DESCRIPTION
        No Azure calls or file writes, so it can be tested with made-up rules.

        -Format ArmTemplate (the default) gives the deployment template the
        Sentinel portal exports and Sentinel Repositories deploy: a workspace
        parameter, and the rule as a Microsoft.OperationalInsights/workspaces/
        providers/alertRules (or automationRules) resource. A string that
        starts with '[' (a display name such as "[Preview] ...") gets a second
        '[', so ARM reads it as text and not as a template expression.
        -Format Json gives the rule as the API returns it.

        Either way, properties Azure sets itself (last modified, created by...)
        are left out, and keys are sorted, so exporting an unchanged rule
        twice gives the same file - a clean diff in source control. The
        built-in rule kinds (Fusion, ML behaviour analytics, threat
        intelligence) keep only what can be set on them.

        Returns @{ Name; Type; Kind; Enabled; RuleId; FileName; Content }, in
        the order given. File names come from the display name, made safe for
        any file system; two rules with one name get their rule ID added.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [AllowEmptyCollection()]
        [object[]] $AnalyticsRule = @(),

        [AllowEmptyCollection()]
        [object[]] $AutomationRule = @(),

        [ValidateSet('ArmTemplate', 'Json')]
        [string] $Format = 'ArmTemplate',

        [string] $ApiVersion = '2025-09-01'
    )

    $readOnly = @{
        alertRules      = @('lastModifiedUtc')
        automationRules = @('createdTimeUtc', 'lastModifiedTimeUtc', 'createdBy', 'lastModifiedBy')
    }
    # Only these can be set on the built-in kinds; the rest comes from their template.
    $settable = @{
        Fusion               = @('alertRuleTemplateName', 'enabled', 'sourceSettings', 'scenarioExclusionPatterns')
        MLBehaviorAnalytics  = @('alertRuleTemplateName', 'enabled')
        ThreatIntelligence   = @('alertRuleTemplateName', 'enabled')
    }
    # Sorted keys at every level, and for a template, '[' doubled at the start of a string.
    $tidy = $null
    $tidy = {
        param($Value, [bool] $Escape)
        if ($Value -is [System.Collections.IDictionary]) {
            $sorted = [ordered]@{}
            # Ordinal, so the order is the same whatever the machine's culture.
            [string[]] $keys = @($Value.Keys | ForEach-Object { [string]$_ })
            [System.Array]::Sort($keys, [System.StringComparer]::Ordinal)
            foreach ($k in $keys) { $sorted[$k] = & $tidy $Value[$k] $Escape }
            return $sorted
        }
        if ($Value -is [string]) { if ($Escape -and $Value.StartsWith('[')) { return "[$Value" }; return $Value }
        if ($Value -is [System.Collections.IEnumerable]) { return , @(foreach ($v in $Value) { & $tidy $v $Escape }) }
        $Value
    }
    $safeName = {
        param([string] $Text)
        $clean = ($Text -replace '[\\/:*?"<>|\x00-\x1f]', '-' -replace '\s+', ' ' -replace '-{2,}', '-').Trim(' ', '.', '-')
        if ($clean.Length -gt 100) { $clean = $clean.Substring(0, 100).TrimEnd(' ', '.', '-') }
        if (-not $clean) { $clean = 'rule' }
        $clean
    }

    $prepared = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($pair in @(@('alertRules', $AnalyticsRule), @('automationRules', $AutomationRule))) {
        $collection = [string]$pair[0]
        foreach ($rule in @($pair[1] | Where-Object { $_ -is [System.Collections.IDictionary] })) {
            $source = $rule['properties']
            if ($source -isnot [System.Collections.IDictionary]) { $source = @{} }
            $kind = if ($rule.Contains('kind')) { [string]$rule['kind'] } else { '' }
            $properties = @{}
            foreach ($k in $source.Keys) {
                if ($readOnly[$collection] -contains $k) { continue }
                if ($settable.Contains($kind) -and $settable[$kind] -notcontains $k) { continue }
                $properties[$k] = $source[$k]
            }
            $ruleId = [string]$rule['name']
            $displayName = [string]$source['displayName']
            $enabled = if ($collection -eq 'alertRules') { [bool]$source['enabled'] } else { [bool]($source['triggeringLogic'] -is [System.Collections.IDictionary] -and $source['triggeringLogic']['isEnabled']) }
            $document = if ($Format -eq 'Json') {
                $raw = [ordered]@{ name = $ruleId }
                if ($kind) { $raw['kind'] = $kind }
                $raw['properties'] = & $tidy $properties $false
                $raw
            }
            else {
                $resource = [ordered]@{
                    id         = "[concat(resourceId('Microsoft.OperationalInsights/workspaces/providers', parameters('workspace'), 'Microsoft.SecurityInsights'),'/$collection/$ruleId')]"
                    name       = "[concat(parameters('workspace'),'/Microsoft.SecurityInsights/$ruleId')]"
                    type       = "Microsoft.OperationalInsights/workspaces/providers/$collection"
                }
                if ($kind) { $resource['kind'] = $kind }
                $resource['apiVersion'] = $ApiVersion
                $resource['properties'] = & $tidy $properties $true
                [ordered]@{
                    '$schema'      = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#'
                    contentVersion = '1.0.0.0'
                    parameters     = [ordered]@{ workspace = [ordered]@{ type = 'String' } }
                    resources      = @($resource)
                }
            }
            $content = (ConvertTo-Json -InputObject $document -Depth 100) -replace "`r`n", "`n"
            $prepared.Add(@{
                    Name     = $(if ($displayName) { $displayName } else { $ruleId })
                    Type     = $(if ($collection -eq 'alertRules') { 'Analytics rule' } else { 'Automation rule' })
                    Kind     = $kind
                    Enabled  = $enabled
                    RuleId   = $ruleId
                    Base     = (& $safeName $(if ($displayName) { $displayName } else { $ruleId }))
                    Folder   = $(if ($collection -eq 'alertRules') { '' } else { 'AutomationRules' })
                    Content  = $content
                })
        }
    }
    # Two rules with one display name would overwrite each other's file.
    $taken = @{}
    foreach ($item in $prepared) { $k = "$($item.Folder)/$($item.Base)".ToLowerInvariant(); $taken[$k] = 1 + [int]$taken[$k] }
    foreach ($item in $prepared) {
        $base = $item.Base
        if ($taken["$($item.Folder)/$base".ToLowerInvariant()] -gt 1) { $base = "$base-$(($item.RuleId -replace '[^A-Za-z0-9-]', '') | ForEach-Object { if ($_.Length -gt 8) { $_.Substring(0, 8) } else { $_ } })" }
        $fileName = if ($item.Folder) { "$($item.Folder)/$base.json" } else { "$base.json" }
        @{ Name = $item.Name; Type = $item.Type; Kind = $item.Kind; Enabled = $item.Enabled; RuleId = $item.RuleId; FileName = $fileName; Content = $item.Content }
    }
}
