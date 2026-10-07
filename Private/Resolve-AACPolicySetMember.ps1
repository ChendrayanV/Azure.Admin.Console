function Resolve-AACPolicySetMember {
    <#
    .SYNOPSIS
        The member policies of an assigned initiative, each with the value
        every one of its parameters ends up with - through the initiative's
        parameters and the assignment's - and its effect.
    .DESCRIPTION
        -Member are the initiative's properties.policyDefinitions
        (policyDefinitionId, policyDefinitionReferenceId, parameters,
        groupNames). -SetParameter are the initiative's parameter
        definitions, -Assigned the assignment's parameters ({ name: { value
        } }), -Override the assignment's overrides. -Definition maps a
        definition's lower-case ID to its definition; parameters, rule,
        displayName, name, policyType and category (or metadata.category)
        are read from it whatever their case.

        A member's parameter takes, in this order:
          [parameters('x')] in the initiative   the assignment's x (Assigned),
                                               else x's default in the
                                               initiative (Initiative default),
                                               else Not set
          another [expression]                 left as written (Expression)
          a value in the initiative            that value (Initiative)
          nothing in the initiative            the policy's default (Policy
                                               default), else Not set
        The effect is the rule's then.effect, its [parameters()] resolved
        the same way - or the assignment's policyEffect override that
        selects the member (Override).

        Returns one hashtable per member: ReferenceId, DefinitionId,
        Definition (or $null when it couldn't be read), Groups, Effect,
        EffectSource, Values (parameter name -> effective value, for
        Get-AACPolicyResourceType) and Parameters (Name, DisplayName, Type,
        DefaultValue, HasDefault, SetValue, SetParameter, Value, Source,
        AllowedValues).
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $Member,

        [AllowNull()]
        $SetParameter,

        [AllowNull()]
        $Assigned,

        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]] $Override,

        [System.Collections.IDictionary] $Definition = @{}
    )

    $get = {
        param($Map, [string] $Name)
        if ($Map -isnot [System.Collections.IDictionary]) { return }
        foreach ($k in $Map.Keys) { if ($k -eq $Name) { return $Map[$k] } }
    }
    $has = {
        param($Map, [string] $Name)
        if ($Map -isnot [System.Collections.IDictionary]) { return $false }
        foreach ($k in $Map.Keys) { if ($k -eq $Name) { return $true } }
        $false
    }
    $reference = "^\[parameters\('([^']+)'\)\]$"

    # The effect overrides: those with no selector apply to every member.
    $effectOverride = {
        param([string] $ReferenceId)
        foreach ($item in @($Override)) {
            if ([string](& $get $item 'kind') -ne 'policyEffect') { continue }
            $selectors = @(& $get $item 'selectors' | Where-Object { $_ -is [System.Collections.IDictionary] -and [string](& $get $_ 'kind') -eq 'policyDefinitionReferenceId' })
            $selected = -not $selectors.Count
            foreach ($selector in $selectors) {
                if (& $has $selector 'in') { if (@(& $get $selector 'in') -contains $ReferenceId) { $selected = $true } }
                elseif (& $has $selector 'notIn') { if (@(& $get $selector 'notIn') -notcontains $ReferenceId) { $selected = $true } }
            }
            if ($selected) { return [string](& $get $item 'value') }
        }
    }

    foreach ($m in @($Member)) {
        if ($m -isnot [System.Collections.IDictionary]) { continue }
        $definitionId = [string](& $get $m 'policyDefinitionId')
        $referenceId = [string](& $get $m 'policyDefinitionReferenceId')
        $policy = $Definition[$definitionId.ToLowerInvariant()]
        $specs = & $get $policy 'parameters'
        $refs = & $get $m 'parameters'
        $values = [ordered]@{}
        $parameters = [System.Collections.Generic.List[object]]::new()
        $names = @(if ($specs -is [System.Collections.IDictionary]) { $specs.Keys } elseif ($refs -is [System.Collections.IDictionary]) { $refs.Keys })
        foreach ($name in $names) {
            $spec = & $get $specs $name
            $entry = @{
                Name = [string]$name; DisplayName = [string](& $get (& $get $spec 'metadata') 'displayName'); Type = [string](& $get $spec 'type')
                HasDefault = & $has $spec 'defaultValue'; DefaultValue = & $get $spec 'defaultValue'; AllowedValues = & $get $spec 'allowedValues'
                SetValue = $null; SetParameter = ''; Value = $null; Source = 'Not set'
            }
            if (& $has $refs $name) {
                $entry.SetValue = & $get (& $get $refs $name) 'value'
                if ($entry.SetValue -is [string] -and $entry.SetValue -match $reference) {
                    $entry.SetParameter = $Matches[1]
                    if (& $has $Assigned $entry.SetParameter) { $entry.Value = & $get (& $get $Assigned $entry.SetParameter) 'value'; $entry.Source = 'Assigned' }
                    elseif (& $has (& $get $SetParameter $entry.SetParameter) 'defaultValue') { $entry.Value = & $get (& $get $SetParameter $entry.SetParameter) 'defaultValue'; $entry.Source = 'Initiative default' }
                }
                elseif ($entry.SetValue -is [string] -and $entry.SetValue.StartsWith('[') -and -not $entry.SetValue.StartsWith('[[')) { $entry.Value = $entry.SetValue; $entry.Source = 'Expression' }
                else { $entry.Value = $entry.SetValue; $entry.Source = 'Initiative' }
            }
            elseif ($entry.HasDefault) { $entry.Value = $entry.DefaultValue; $entry.Source = 'Policy default' }
            $values[[string]$name] = $entry.Value
            $parameters.Add($entry)
        }

        $effect = [string](& $get (& $get (& $get $policy 'rule') 'then') 'effect')
        $effectSource = 'Policy'
        if ($effect -match $reference) {
            $effectName = $Matches[1]
            $effect = [string](& $get $values $effectName)
            $effectSource = [string](@($parameters | Where-Object Name -EQ $effectName | ForEach-Object Source) | Select-Object -First 1)
        }
        $overridden = & $effectOverride $referenceId
        if ($overridden) { $effect = $overridden; $effectSource = 'Override' }

        @{
            ReferenceId  = $referenceId
            DefinitionId = $definitionId
            Definition   = $policy
            Groups       = @(& $get $m 'groupNames' | Where-Object { $_ })
            Effect       = $effect
            EffectSource = $effectSource
            Values       = $values
            Parameters   = $parameters.ToArray()
        }
    }
}
