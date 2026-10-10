function ConvertTo-AACConfigurationDrift {
    <#
    .SYNOPSIS
        Compares the deployed configuration with its desired state - a saved
        baseline, desired-state rules, Terraform's view of the
        infrastructure - and says what drifted, who or what changed it, and
        what to do about it.
    .DESCRIPTION
        Sources:
          Baseline   -Baseline (a snapshot saved earlier) against -Current:
                     each setting changed, added or removed; resources
                     created or deleted since
          Rule       each -Rule against -Current: a setting that isn't as
                     the rule expects
          Terraform  -TerraformDrift (a plan's resource_drift): what changed
                     outside Terraform
        Why: the latest change Resource Graph recorded (-Change, 14 days)
        to the resource, or to that setting - who (changedBy), when, and
        its origin: Manual (a person), Automation (an application or
        pipeline) or Azure (a platform update).
        Strategy: Fix (a rule broken), Revert or Re-deploy (a manual change
        to what infrastructure as code or the baseline says), Update the
        baseline (an Azure or pipeline change that's probably intended),
        Review (unknown origin) - with the remediation.
        Severity: a rule's own; for the baseline and Terraform, High when
        the setting is about security or networking (TLS, public access,
        firewall and network rules, encryption, identity, authentication,
        keys), Medium otherwise; resources created or deleted Low.
        Returns @{ Drift (AAC.ConfigurationDrift); Stats }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        # ConvertTo-AACConfigurationSnapshot's result for now.
        [hashtable] $Current = @{},
        # A snapshot saved earlier (or $null).
        [hashtable] $Baseline,
        [AllowEmptyCollection()] [object[]] $Rule = @(),
        # Terraform plan resource_drift entries.
        [AllowEmptyCollection()] [object[]] $TerraformDrift = @(),
        # Resource Graph resourcechanges rows: resourceId, at, changedBy, clientType, changes.
        [AllowEmptyCollection()] [object[]] $Change = @(),
        [System.Collections.IDictionary] $SubscriptionName = @{}
    )

    $get = { param($Row, [string] $Name) if ($Row -is [System.Collections.IDictionary]) { $Row[$Name] } elseif ($null -ne $Row) { $p = $Row.PSObject.Properties[$Name]; if ($p) { $p.Value } } }
    $subOf = { param($Id) if ([string]$Id -match '(?i)^/subscriptions/([^/]+)') { $s = $Matches[1].ToLowerInvariant(); if ($SubscriptionName.Contains($s)) { [string]$SubscriptionName[$s] } else { $s } } else { '' } }
    $sensitive = '(?i)tls|ssl|https|publicnetworkaccess|public|firewall|networkacls|ipRules|virtualNetworkRules|securityRules|encryption|identity|auth|sharedkey|localaccount|accesspolicies|rbac|softdelete|purge|adminuser|nonsslport|keyvault|key'
    $severity = Get-AACSeverityRank

    # --- Who changed what (Resource Graph's change history) ----------------------------------------------------------
    $byResource = @{}
    foreach ($c in $Change) {
        $id = ([string](& $get $c 'resourceId')).ToLowerInvariant()
        if (-not $byResource.Contains($id)) { $byResource[$id] = [System.Collections.Generic.List[object]]::new() }
        $byResource[$id].Add($c)
    }
    $why = {
        # The latest recorded change to the setting - or to the resource.
        param([string] $Id, [string] $Path)
        $changes = @(@(if ($byResource.Contains($Id)) { $byResource[$Id] }) | Sort-Object -Property { [string](& $get $_ 'at') } -Descending)
        $hit = @($changes | Where-Object { $Path -and (& $get $_ 'changes') -is [System.Collections.IDictionary] -and (& $get $_ 'changes').Contains($Path) }) | Select-Object -First 1
        $category = ''
        if ($hit) { $category = [string](& $get (& $get $hit 'changes')[$Path] 'changeCategory') } else { $hit = $changes | Select-Object -First 1 }
        if (-not $hit) { return @{ By = ''; At = $null; Origin = 'Unknown' } }
        $by = [string](& $get $hit 'changedBy')
        $at = & $get $hit 'at'
        $origin = if ($category -eq 'System' -or $by -match '(?i)^(Microsoft\.|System|Azure)') { 'Azure' } elseif ($by -match '@') { 'Manual' } elseif ($by) { 'Automation' } else { 'Unknown' }
        @{ By = $by; At = $(if ($at -is [datetime]) { $at } elseif ($at) { [datetime]::Parse([string]$at, [cultureinfo]::InvariantCulture).ToUniversalTime() } else { $null }); Origin = $origin }
    }
    $strategyFor = {
        param([string] $Source, [string] $Origin)
        if ($Source -eq 'Rule') { return @{ Strategy = 'Fix'; Text = '' } }
        switch ($Origin) {
            'Manual' { @{ Strategy = $(if ($Source -eq 'Terraform') { 'Re-deploy' } else { 'Revert' }); Text = $(if ($Source -eq 'Terraform') { 'Changed by hand outside Terraform: apply the configuration again (terraform apply), or bring the change into the code if it should stay.' } else { 'Changed by hand: set it back, or - if it should stay - save a new baseline (-SaveBaseline) and put it in the infrastructure as code.' }) } }
            'Azure' { @{ Strategy = 'Update the baseline'; Text = 'Changed by Azure (a platform update or default): accept it - save a new baseline, or update the infrastructure as code to match.' } }
            'Automation' { @{ Strategy = 'Update the baseline'; Text = 'Changed by an application or pipeline: if that''s the deployment that owns it, accept it and save a new baseline; if not, find out which one did.' } }
            default { @{ Strategy = 'Review'; Text = 'Who changed it isn''t recorded (Resource Graph keeps 14 days): check the Activity Log, then revert it or save a new baseline.' } }
        }
    }
    $drift = [System.Collections.Generic.List[object]]::new()
    $add = {
        param([string] $Severity, [string] $Source, [string] $Kind, [string] $Id, [string] $Type, [string] $Name, [string] $Property, [string] $Expected, [string] $Actual, [string] $Fix)
        $w = & $why $Id $Property
        $plan = & $strategyFor $Source $w.Origin
        $remedy = if ($Fix) { $Fix } else { $plan.Text }
        $drift.Add((New-AACFinding -TypeName 'AAC.ConfigurationDrift' -Severity $Severity -Category $Kind -Finding "$Name$(if ($Property) { ": $Property" }) - $($Kind.ToLowerInvariant())" -ResourceId $(if ($Id -like '/subscriptions/*') { $Id } else { '' }) -Resource $Name -ResourceType $Type `
                    -Subscription (& $subOf $Id) -Detail $(if ($Property) { "$(if ($Expected -ne '') { $Expected } else { '(none)' }) -> $(if ($Actual -ne '') { $Actual } else { '(none)' })" } else { '' }) -Remediation $remedy -Effort $(if ($plan.Strategy -in 'Revert', 'Fix') { 'Low' } elseif ($plan.Strategy -eq 'Re-deploy') { 'Low' } else { 'Medium' }) `
                    -Property ([ordered]@{ Source = $Source; Property = $Property; Expected = $Expected; Actual = $Actual; ChangedBy = $w.By; ChangedAt = $w.At; Origin = $w.Origin; Strategy = $plan.Strategy })))
    }
    $sev = { param([string] $Path) if ($Path -match $sensitive) { 'High' } else { 'Medium' } }

    # --- Against the baseline ------------------------------------------------------------------------------------------
    if ($null -ne $Baseline) {
        foreach ($id in $Current.Keys) {
            $now = $Current[$id]
            if (-not $Baseline.Contains($id)) { & $add 'Low' 'Baseline' 'New resource' $id $now.Type $now.Name '' '' '' 'Created since the baseline: if it''s meant to be there, save a new baseline; if not, find who created it and remove it.'; continue }
            $was = $Baseline[$id]
            $wasValues = $was.Settings
            foreach ($path in @(@($now.Settings.Keys) + @($wasValues.Keys) | Select-Object -Unique | Sort-Object)) {
                $before = if ($wasValues.Contains($path)) { [string]$wasValues[$path] } else { $null }
                $after = if ($now.Settings.Contains($path)) { [string]$now.Settings[$path] } else { $null }
                if ($before -ceq $after) { continue }
                $kind = if ($null -eq $before) { 'Added' } elseif ($null -eq $after) { 'Removed' } else { 'Changed' }
                & $add (& $sev $path) 'Baseline' $kind $id $now.Type $now.Name $path $(if ($null -ne $before) { $before } else { '' }) $(if ($null -ne $after) { $after } else { '' }) ''
            }
        }
        foreach ($id in $Baseline.Keys) {
            if ($Current.Contains($id)) { continue }
            $was = $Baseline[$id]
            & $add 'Medium' 'Baseline' 'Deleted resource' $id ([string]$was.Type) ([string]$was.Name) '' '' '' 'Deleted since the baseline: if that was intended, save a new baseline; if not, recreate it from infrastructure as code or a backup.'
        }
    }

    # --- Against the rules -------------------------------------------------------------------------------------------------
    foreach ($id in $Current.Keys) {
        $now = $Current[$id]
        foreach ($r in @($Rule | Where-Object { $now.Type -like $_.ResourceType })) {
            $actual = if ($now.Settings.Contains($r.Property)) { [string]$now.Settings[$r.Property] } else { $null }
            $expected = @($r.Expected | ForEach-Object { [string]$_ })
            $ok = switch ($r.Operator) {
                'Equals' { $null -ne $actual -and $actual -eq $expected[0] }
                'NotEquals' { $actual -ne $expected[0] }
                'In' { $null -ne $actual -and @($expected | Where-Object { $_ -eq $actual }).Count -gt 0 }
                'Match' { $null -ne $actual -and $actual -match $expected[0] }
                'Exists' { $null -ne $actual }
            }
            if ($ok) { continue }
            & $add $r.Severity 'Rule' 'Violation' $id $now.Type $now.Name $r.Property $(switch ($r.Operator) { 'In' { "one of $($expected -join ', ')" } 'NotEquals' { "not $($expected[0])" } 'Match' { "matching $($expected[0])" } 'Exists' { 'set' } default { $expected[0] } }) $(if ($null -ne $actual) { $actual } else { '' }) $r.Remediation
        }
    }

    # --- Terraform: what changed outside it ------------------------------------------------------------------------------
    foreach ($t in $TerraformDrift) {
        $tfChange = & $get $t 'change'
        $before = & $get $tfChange 'before'; $after = & $get $tfChange 'after'
        $address = [string](& $get $t 'address')
        $id = ([string]$(if (& $get $after 'id') { & $get $after 'id' } elseif (& $get $before 'id') { & $get $before 'id' } else { $address })).ToLowerInvariant()
        $flatBefore = (ConvertTo-AACConfigurationSnapshot -Resource @(@{ id = $id; type = 'x'; name = ''; properties = $before }))[$id]['Settings']
        $flatAfter = (ConvertTo-AACConfigurationSnapshot -Resource @(@{ id = $id; type = 'x'; name = ''; properties = $after }))[$id]['Settings']
        $actions = @(& $get $tfChange 'actions')
        if ($actions -contains 'delete') { & $add 'Medium' 'Terraform' 'Deleted resource' $id ([string](& $get $t 'type')) $address '' '' '' 'Deleted outside Terraform: run terraform apply to recreate it, or remove it from the code.'; continue }
        foreach ($path in @(@($flatBefore.Keys) + @($flatAfter.Keys) | Select-Object -Unique | Sort-Object)) {
            $b = if ($flatBefore.Contains($path)) { [string]$flatBefore[$path] } else { $null }
            $a = if ($flatAfter.Contains($path)) { [string]$flatAfter[$path] } else { $null }
            if ($b -ceq $a) { continue }
            $attribute = $path -replace '^properties\.', ''
            & $add (& $sev $attribute) 'Terraform' $(if ($null -eq $b) { 'Added' } elseif ($null -eq $a) { 'Removed' } else { 'Changed' }) $id ([string](& $get $t 'type')) $address $attribute $(if ($null -ne $b) { $b } else { '' }) $(if ($null -ne $a) { $a } else { '' }) ''
        }
    }

    $sorted = @($drift | Sort-Object -Property @{ Expression = { $severity.Rank[$_.Severity] } }, Source, Resource, Property)
    @{
        Drift = $sorted
        Stats = @{
            Items     = $sorted.Count
            Resources = @($sorted | ForEach-Object { if ($_.ResourceId) { $_.ResourceId } else { $_.Resource } } | Select-Object -Unique).Count
            High      = @($sorted | Where-Object Severity -In 'Critical', 'High').Count
            Manual    = @($sorted | Where-Object Origin -EQ 'Manual').Count
            Violations = @($sorted | Where-Object Source -EQ 'Rule').Count
            # A resource deleted since the baseline was checked too.
            Checked   = @(@($Current.Keys) + @(if ($null -ne $Baseline) { $Baseline.Keys }) | Select-Object -Unique).Count
        }
    }
}
