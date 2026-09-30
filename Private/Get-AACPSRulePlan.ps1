function Get-AACPSRulePlan {
    <#
    .SYNOPSIS
        Works out what Invoke-AACPSRule has to read for the rules asked for -
        and refuses a -Rule that can't match anything - before any Azure call.
    .DESCRIPTION
        -Rule takes rule names or wildcards. A file path given there (a
        common slip for -RulePath) and an AAC.* name the module doesn't have
        are refused with what to use instead.

        When only the module's own AAC.* rules run (every -Rule starts with
        'AAC.', no -Baseline, no -RulePath), the child settings PSRule for
        Azure's rules need - diagnostic settings, blob services, API
        Management APIs, ... one to hundreds of Azure Resource Manager calls
        per resource - aren't read: the AAC rules look only at names, types
        and tags, which Resource Graph returns. -NoExpand asks for the same
        with your own rules.

        When the only rule left is AAC.Resource.Naming and no -ResourceType
        is given, only the types it checks are read: the table in
        PSRule\Rules\AAC.Naming.Rule.ps1 (read without running the file),
        with -Configuration's AAC_NAMING_PATTERNS added ('' removes a type).

        A tag rule asked for with no tags to check - none in -Configuration
        and none in Get-AACTagDefault (PSRule\Rules\AAC.Tags.Rule.ps1) -
        would silently return nothing; Notice says so, and how to name them.

        Returns @{ Expand; ResourceType; Read (what is read, in words);
        Notice (lines to show) }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [string[]] $Rule = @(),
        [string[]] $ExcludeRule = @(),
        [string[]] $RulePath = @(),
        [string] $Baseline,
        [string[]] $ResourceType = @(),
        [hashtable] $Configuration = @{},
        [switch] $NoExpand
    )

    $rulesFolder = Join-Path -Path $script:AACModuleRoot -ChildPath 'PSRule/Rules'
    $known = @(Get-ChildItem -LiteralPath $rulesFolder -Filter '*.Rule.ps1' | ForEach-Object {
            [regex]::Matches((Get-Content -LiteralPath $_.FullName -Raw), "(?m)^\s*Rule\s+'([^']+)'") | ForEach-Object { $_.Groups[1].Value }
        })

    # --- -Rule: names, not files -------------------------------------------------------------
    foreach ($name in $Rule) {
        if ($name -match '[\\/]|\.(ps1|ya?ml|jsonc?)$') {
            throw "-Rule takes rule names or wildcards, such as 'AAC.Resource.Naming' or 'Azure.Storage.*' - '$name' looks like a file. The module's own rules (PSRule\Rules) always load; to add rule files of your own, pass them to -RulePath."
        }
        if ($name -like 'AAC.*' -and -not [System.Management.Automation.WildcardPattern]::ContainsWildcardCharacters($name) -and $known -notcontains $name) {
            throw "The module has no rule named '$name'. Its rules are: $(($known | Sort-Object) -join ', ')."
        }
    }

    # --- Only the module's own rules? ----------------------------------------------------------
    $aacOnly = $Rule.Count -gt 0 -and -not $Baseline -and -not $RulePath.Count -and -not @($Rule | Where-Object { $_ -notlike 'AAC.*' }).Count
    $selected = @($known | Where-Object {
            $name = $_
            (-not $Rule.Count -or @($Rule | Where-Object { $name -like $_ }).Count) -and -not @($ExcludeRule | Where-Object { $name -like $_ }).Count
        })
    $plan = @{
        Expand       = -not ($aacOnly -or $NoExpand)
        ResourceType = @($ResourceType)
        Read         = ''
        Notice       = @()
    }
    # --- Tag rules with nothing to check ---------------------------------------------------------
    $tagRules = @($selected | Where-Object { $_ -in 'AAC.Resource.RequiredTags', 'AAC.ResourceGroup.RequiredTags', 'AAC.Resource.AllowedTagValues' })
    if ($tagRules.Count -and ($Rule.Count -or -not $Configuration.Count)) {
        $tags = Get-AACRuleDefault -File 'AAC.Tags.Rule.ps1' -Function 'Get-AACTagDefault'
        $required = @(@($Configuration['AAC_REQUIRED_TAGS']) + @($tags['RequiredTags']) | Where-Object { $_ })
        $allowed = $Configuration['AAC_ALLOWED_TAG_VALUES']
        if ($null -eq $allowed -and $tags['AllowedValues'] -and $tags['AllowedValues'].Count) { $allowed = $tags['AllowedValues'] }
        $idle = @($tagRules | Where-Object { ($_ -like '*RequiredTags' -and -not $required.Count) -or ($_ -eq 'AAC.Resource.AllowedTagValues' -and $null -eq $allowed) })
        # Without -Rule, only say so when the tag rules were asked for by name - a plain run shouldn't nag.
        $named = @($idle | Where-Object { $name = $_; @($Rule | Where-Object { $name -like $_ }).Count })
        if ($named.Count) {
            $plan.Notice = @("$($named -join ', ') checked nothing: no tags are named. Name them with -Configuration @{ AAC_REQUIRED_TAGS = @('Owner', 'CostCenter'); AAC_ALLOWED_TAG_VALUES = @{ Environment = @('prod', 'test', 'dev') } }, or once for every run in Get-AACTagDefault (PSRule\Rules\AAC.Tags.Rule.ps1).")
        }
    }
    if (-not $plan.Expand) {
        $plan.Read = 'names, types and tags from Resource Graph (no child settings)'
    }

    # --- Naming alone: only the types it checks ------------------------------------------------
    if ($aacOnly -and $selected.Count -eq 1 -and $selected[0] -eq 'AAC.Resource.Naming' -and -not $ResourceType.Count) {
        $types = [ordered]@{}
        $defaults = Get-AACRuleDefault -File 'AAC.Naming.Rule.ps1' -Function 'Get-AACNamingDefault'
        foreach ($key in $defaults.Keys) { if ($defaults[$key]) { $types[([string]$key).ToLowerInvariant()] = [string]$key } }
        $overrides = $Configuration['AAC_NAMING_PATTERNS']
        if ($overrides -is [System.Collections.IDictionary]) {
            foreach ($key in $overrides.Keys) {
                $lower = ([string]$key).ToLowerInvariant()
                if ($overrides[$key]) { $types[$lower] = [string]$key } else { $types.Remove($lower) }
            }
        }
        if ($types.Count) {
            $plan.ResourceType = @($types.Values)
            $plan.Read = "the $($types.Count) resource types the naming rule checks, from Resource Graph (no child settings)"
        }
    }
    $plan
}
