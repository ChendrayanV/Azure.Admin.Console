function ConvertTo-AACServiceBlueprint {
    <#
    .SYNOPSIS
        Brings a blueprint's names, Azure Policy and PSRule results together:
        the findings, and each component's counts and status.
    .DESCRIPTION
        Severity: Blocking is what Azure would refuse (an invalid name, a
        Deny, a guardrail); PSRule's Critical is High, Important is Medium,
        anything else Low; a policy's Audit is Medium and a change by policy
        Low. Status: Blocked, Needs attention (a High or Medium finding) or
        Ready. Not checked is never Ready: without a policy verdict or PSRule
        it says so, and a component that would otherwise look clean stays
        Not fully checked. A component with no planned body can only ever be Not
        fully checked or Blocked. AMBA's alerts and APRL's recommendations are
        suggestions, not results, so they are counted but don't change a status.

        Returns @{ Components (AAC.ServiceBlueprintComponent); Findings
        (AAC.ServiceBlueprintFinding); Stats }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Component,

        # Read-AACServiceBlueprintPolicy's result, or $null when no scope was given.
        [AllowNull()]
        [System.Collections.IDictionary] $Policy,

        # Invoke-AACPSRuleEngine's results, or $null when it didn't run.
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $PSRuleResult
    )

    $findings = [System.Collections.Generic.List[object]]::new()
    $add = {
        param([string] $Severity, [string] $Source, [string] $ComponentName, [string] $Item, [string] $Detail, [string] $Fix = '', [string] $Link = '', [string] $ComponentId = '')
        $findings.Add([pscustomobject][ordered]@{ PSTypeName = 'AAC.ServiceBlueprintFinding'; Severity = $Severity; Source = $Source; Component = $ComponentName; Item = $Item; Detail = $Detail; Fix = $Fix; Link = $Link; ComponentId = $ComponentId })
    }
    $psruleSeverity = @{ Critical = 'High'; Important = 'Medium' }
    $guardrails = if ($Policy) { @($Policy.Guardrails) } else { @() }
    foreach ($guard in @($guardrails | Where-Object { $_.Outcome -eq 'Blocks' -and -not $_.ComponentId })) { & $add 'Blocking' 'Guardrail' '(all)' $guard.Guardrail $guard.Detail 'Pick an allowed value, or ask for an exemption.' }

    $components = @(foreach ($item in $Component) {
            if ($item.Problem) { & $add 'Blocking' 'Naming' $item.Name 'Name' $item.Problem 'Shorten -Workload or change -NamingConvention.' '' $item.Id }
            foreach ($guard in @($guardrails | Where-Object { $_.Outcome -eq 'Blocks' -and $_.ComponentId -eq $item.Id })) { & $add 'Blocking' 'Guardrail' $item.Name $guard.Guardrail "$($guard.Detail) $($guard.Assignment)".Trim() 'Choose another service, or ask for an exemption.' '' $item.Id }
            $verdict = if ($Policy -and $Policy.Verdicts.ContainsKey($item.Id)) { $Policy.Verdicts[$item.Id] } else { $null }
            foreach ($evaluation in @(if ($verdict) { $verdict.Evaluations })) {
                $severity = switch ($evaluation.Outcome) { 'Blocks' { 'Blocking' } 'Audits' { 'Medium' } default { 'Low' } }
                & $add $severity 'Azure Policy' $item.Name $evaluation.Assignment "$($evaluation.Effect): $($evaluation.Detail)".TrimEnd(': ') $(if ($evaluation.Outcome -eq 'Blocks') { 'Change the planned configuration to meet it, or ask for an exemption.' }) '' $item.Id
            }
            foreach ($restriction in @(if ($verdict) { $verdict.Restrictions | Where-Object { $_.Field -ne 'location' -and $_.Result -eq 'Required' -and $_.DefaultValue } })) {
                & $add 'Low' 'Azure Policy' $item.Name $restriction.Assignment "Sets $($restriction.Field) to '$($restriction.DefaultValue)' when it isn't given." '' '' $item.Id
            }
            $results = @($PSRuleResult | Where-Object { $_ -and $_.ResourceName -eq $item.Name })
            foreach ($result in @($results | Where-Object Outcome -In 'Fail', 'Error')) {
                & $add $(if ($psruleSeverity.ContainsKey([string]$result.Severity)) { $psruleSeverity[[string]$result.Severity] } else { 'Low' }) 'PSRule' $item.Name $result.RuleName "$($result.Title)$(if ($result.Reason) { " - $($result.Reason)" })" $result.Recommendation $result.Link $item.Id
            }
            $own = @($findings | Where-Object ComponentId -EQ $item.Id)
            $policyRows = @(if ($Policy) { $Policy.Policies | Where-Object ComponentId -EQ $item.Id })
            $policyChecked = [bool]($verdict -and $verdict.Checked)
            $psruleChecked = $null -ne $PSRuleResult -and [bool]$item.Resource
            $status = if (@($own | Where-Object Severity -EQ 'Blocking').Count) { 'Blocked' }
            elseif (@($own | Where-Object Severity -In 'High', 'Medium').Count) { 'Needs attention' }
            elseif (-not $policyChecked -or -not $psruleChecked) { 'Not fully checked' }
            else { 'Ready' }
            [pscustomobject][ordered]@{
                PSTypeName = 'AAC.ServiceBlueprintComponent'; Id = $item.Id; Service = $item.Service; Name = $item.Name; Label = $item.Label; ResourceType = $item.Type; Region = $item.Location; Sku = $item.Sku; Icon = $item.Icon; Status = $status
                PoliciesAssigned = $policyRows.Count; PolicyChecked = $policyChecked; Blocks = @($own | Where-Object { $_.Source -in 'Azure Policy', 'Guardrail' -and $_.Severity -eq 'Blocking' }).Count; Audits = @($own | Where-Object { $_.Source -eq 'Azure Policy' -and $_.Severity -eq 'Medium' }).Count
                PSRuleChecked = $psruleChecked; PSRulePassed = @($results | Where-Object Outcome -EQ 'Pass').Count; PSRuleFailed = @($results | Where-Object Outcome -In 'Fail', 'Error').Count; NameAdjusted = [bool]$item.Adjusted; NameProblem = [string]$item.Problem
                Planned = [bool]$item.Resource; BaselineAlerts = @($item['Alerts']).Where({ $_ }).Count; ResiliencyTotal = @($item['Resiliency']).Where({ $_ }).Count; ResiliencyHigh = @($item['Resiliency']).Where({ $_ -and $_.Impact -eq 'High' }).Count
            }
        })

    $order = @{ Blocking = 0; High = 1; Medium = 2; Low = 3 }
    $sorted = @($findings | Sort-Object -Property @{ Expression = { $order[$_.Severity] } }, Component, Source, Item)
    @{
        Components = $components
        Findings   = $sorted
        Stats      = @{
            Components = $components.Count; Blocked = @($components | Where-Object Status -EQ 'Blocked').Count; Attention = @($components | Where-Object Status -EQ 'Needs attention').Count; Ready = @($components | Where-Object Status -EQ 'Ready').Count; NotChecked = @($components | Where-Object Status -EQ 'Not fully checked').Count
            Blocking = @($sorted | Where-Object Severity -EQ 'Blocking').Count; High = @($sorted | Where-Object Severity -EQ 'High').Count; Medium = @($sorted | Where-Object Severity -EQ 'Medium').Count; Low = @($sorted | Where-Object Severity -EQ 'Low').Count
        }
    }
}
