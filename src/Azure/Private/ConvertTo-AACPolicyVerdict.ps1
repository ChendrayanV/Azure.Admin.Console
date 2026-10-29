function ConvertTo-AACPolicyVerdict {
    <#
    .SYNOPSIS
        Puts Azure Policy's answer for a planned resource
        (Invoke-AACPolicyRestrictionCheck) on the policies that apply to it
        (ConvertTo-AACEffectivePolicy): which would fail, which pass, which
        act only after the deployment - and the values policy allows.
    .DESCRIPTION
        -Policy are the resource's AAC.EffectivePolicy rows; their State is
        set here:
          Would fail        Azure says the body fails it (Reason and Detail:
                            why, and the field, expected and actual value)
          Passes            a deny, audit, modify or append the body passes
          After deployment  deployIfNotExists, auditIfNotExists and
                            denyAction: they act on what exists afterwards
          Not checked       Azure couldn't be asked (-Checked off)
        A failing policy that isn't in -Policy (read from a scope the
        assignments didn't cover) is added as a row of its own.

        Returns @{ Policies (the added rows); Restrictions
        (AAC.EffectivePolicyRestriction: Field, Rule, Values, Policy,
        Effect, Assignment, Resource); Findings (AAC.EffectivePolicyFinding:
        High for a refusal, Low for an audit, Info for a change) }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [AllowEmptyCollection()]
        [object[]] $Policy = @(),

        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Check,

        [System.Collections.IDictionary] $Definition = @{},

        [string] $ResourceName,

        [string] $ResourceType,

        [string] $ResourceId,

        [switch] $Checked
    )

    $nameOf = { param([string] $Id) $d = $Definition[$Id.ToLowerInvariant()]; if ($d) { [string]$d.DisplayName } elseif ($Id) { ($Id -split '/')[-1] } else { '' } }
    $index = @{}
    foreach ($row in $Policy) { $index["$(([string]$row.AssignmentId).ToLowerInvariant())|$(([string]$row.ReferenceId).ToLowerInvariant())"] = $row }
    $added = [System.Collections.Generic.List[object]]::new()
    $findings = [System.Collections.Generic.List[object]]::new()
    $finding = {
        param([string] $Severity, [string] $PolicyName, [string] $Text, [string] $Detail, [string] $Recommendation)
        $findings.Add([pscustomobject]@{ PSTypeName = 'AAC.EffectivePolicyFinding'; Severity = $Severity; Resource = $ResourceName; Policy = $PolicyName; Finding = $Text; Detail = $Detail; Recommendation = $Recommendation; ResourceId = $ResourceId })
    }

    # The values policy allows or sets, by field.
    $ruleOf = @{ Deny = "Can't be"; Audit = 'Audited when'; Removed = 'Removed by policy' }
    $restrictions = @(foreach ($x in @($Check.Restrictions)) {
            $values = @($x.Values)
            $rule = if ($x.Result -eq 'Required') { if ($null -ne $x.DefaultValue -and -not $values.Count) { 'Set by policy when missing' } else { 'Must be one of' } } elseif ($ruleOf.Contains($x.Result)) { $ruleOf[$x.Result] } else { $x.Result }
            [pscustomobject][ordered]@{
                PSTypeName = 'AAC.EffectivePolicyRestriction'
                Resource   = $ResourceName
                Field      = $x.Field
                Rule       = $rule
                Values     = $(if ($values.Count) { $values -join ', ' } elseif ($null -ne $x.DefaultValue) { Format-AACPolicyValue -Value $x.DefaultValue } else { '' })
                Policy     = (& $nameOf $x.DefinitionId)
                Effect     = $x.Effect
                Assignment = $x.Assignment
            }
        }) | Sort-Object -Property Field, Rule, Values, Policy -Unique

    foreach ($e in @($Check.Evaluations)) {
        $key = "$($e.AssignmentId)|$(([string]$e.ReferenceId).ToLowerInvariant())"
        $row = $index[$key]
        if (-not $row) {
            $impact = switch -Regex ($e.Effect) { '^(?i)deny$' { 'Blocks' } '(?i)audit' { 'Audits' } default { 'Changes' } }
            $row = [pscustomobject][ordered]@{
                PSTypeName = 'AAC.EffectivePolicy'; Resource = $ResourceName; ResourceType = $ResourceType; ResourceGroup = ''; Subscription = ''; Policy = (& $nameOf $e.DefinitionId); Initiative = (& $nameOf $e.SetId)
                ReferenceId = $e.ReferenceId; Assignment = $e.Assignment; AssignedAt = ''; Level = ''; Applicability = 'Applies'; Impact = $impact; Effect = $e.Effect; EffectSource = ''; Enforcement = 'Default'
                State = ''; Evaluated = $null; Reason = ''; Detail = ''; Exemption = ''; ExemptionExpires = $null; Message = ''; Identity = ''; Controls = ''; Targets = ''; Mode = ''; Version = ''
                Category = ''; PolicyType = ''; Parameters = ''; ResourceId = $ResourceId; AssignmentId = $e.AssignmentId; DefinitionId = $e.DefinitionId
            }
            $added.Add($row)
            $index[$key] = $row
        }
        $row.State = 'Would fail'
        $row.Reason = $(if ($e.Reason) { $e.Reason } else { "The planned body fails the policy's rule ($($e.Effect))." })
        $row.Detail = @($e.Expressions) -join '; '
        $fix = @($restrictions | Where-Object { $_.Assignment -eq $e.Assignment -and $_.Rule -in 'Must be one of', "Can't be" } | ForEach-Object { "$($_.Field) $($_.Rule.ToLowerInvariant()): $($_.Values)" })
        switch ($e.Outcome) {
            'Blocks' { & $finding 'High' $row.Policy 'Azure Policy would refuse the deployment' $(if ($row.Detail) { "$($row.Reason) ($($row.Detail))" } else { $row.Reason }) $(if ($fix.Count) { "Use an allowed value - $($fix -join '; ') - or ask for an exemption." } else { 'Change what the policy checks (see the detail), or ask for an exemption before deploying.' }) }
            'Audits' { & $finding 'Low' $row.Policy 'It would deploy, but be reported non-compliant' $(if ($row.Detail) { $row.Detail } else { $row.Reason }) 'Change the setting now to deploy compliant, or accept the audit.' }
            default { & $finding 'Info' $row.Policy "Policy would change it as it deploys ($($e.Effect))" $(if ($row.Detail) { $row.Detail } else { $row.Reason }) 'Set the value in the template, so the deployed resource matches the code.' }
        }
    }

    foreach ($row in @(@($Policy) + $added.ToArray())) {
        if ($row.Applicability -ne 'Applies' -or $row.State -eq 'Would fail') { continue }
        $row.State = if ($row.Effect -in 'DeployIfNotExists', 'AuditIfNotExists', 'DenyAction') { 'After deployment' }
        elseif ($row.Effect -in 'Deny', 'Audit', 'Modify', 'Append') { if ($Checked) { 'Passes' } else { 'Not checked' } }
        else { $row.State }
    }
    @{ Policies = $added.ToArray(); Restrictions = @($restrictions); Findings = $findings.ToArray() }
}
