function Get-AACTemplateResource {
    <#
    .SYNOPSIS
        The resources an ARM template (or a Bicep file compiled to one) would
        deploy, with their expressions worked out where that can be done
        offline - the bodies Test-AACPolicyDeployment sends to Azure Policy.
    .DESCRIPTION
        Reads -Template (ConvertFrom-Json -AsHashtable), its parameters from
        -Parameter (name -> value) or their defaults, and evaluates the
        template language locally: parameters(), variables(), concat,
        format, toLower/toUpper, replace, substring, take, split, join,
        if, coalesce, equals, not/and/or, empty, length, contains, union,
        createObject, createArray, json, string, int, bool, first, last,
        startsWith, endsWith, resourceGroup(), subscription(), deployment(),
        resourceId() and its subscription / tenant / extension forms, and
        copyIndex() (a copy loop is checked for its first instance).

        What can't be known before the deployment - uniqueString(), guid(),
        utcNow(), reference(), list*(), newGuid(), environment(), a
        parameter with no value - is unresolved: the property holding it is
        left out of the body and named in Unresolved, never guessed.

        Nested deployments (Bicep modules) are followed - inner and outer
        expression scope, another resource group - and a template linked by
        URI is reported, not fetched. Child resources declared inside their
        parent get the parent's type and name in front. Symbolic-name
        templates (languageVersion 2.0) work too; 'existing' resources and
        those whose condition is false are skipped.

        Returns @{ Resources; Notices }. Each resource: Type, Name (full,
        parent/child; 'unresolved-name' when it can't be worked out - and
        then left out of Content), Id, ParentId (for a child, or the scope of an
        extension resource), ScopeId (the subscription or resource group it
        is deployed to), ResourceGroup, ApiVersion, Location, Tags, Content
        (the body: type, name, location, tags, sku, kind, identity, zones,
        plan, extendedLocation, properties), Unresolved (property paths),
        Source (the template, or 'module <name>') and Copy.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Template,

        [System.Collections.IDictionary] $Parameter = @{},

        [Parameter(Mandatory)]
        [string] $SubscriptionId,

        [string] $ResourceGroupName,

        # The resource group's location, for resourceGroup().location.
        [string] $Location,

        [string] $Source = 'template'
    )

    $unresolved = [pscustomobject]@{ AACUnresolved = $true }
    $isUnresolved = { param($Value) $null -ne $Value -and [object]::ReferenceEquals($Value, $unresolved) }
    $notices = [System.Collections.Generic.List[string]]::new()
    $resources = [System.Collections.Generic.List[hashtable]]::new()
    $unnamed = @{ Count = 0 }
    # Keeps a one-item list a list ('zones': ['1']).
    $get = {
        param($Map, [string] $Name)
        if ($Map -isnot [System.Collections.IDictionary]) { return }
        foreach ($k in $Map.Keys) { if ($k -eq $Name) { return , $Map[$k] } }
    }
    # 'resources': a list - or, in a symbolic-name template, an object of them.
    $resourceList = { param($Value) if ($Value -is [System.Collections.IDictionary] -and -not (& $has $Value 'type')) { @($Value.Values) } elseif ($null -ne $Value) { @($Value) } }
    $has = {
        param($Map, [string] $Name)
        if ($Map -isnot [System.Collections.IDictionary]) { return $false }
        foreach ($k in $Map.Keys) { if ($k -eq $Name) { return $true } }
        $false
    }

    # --- The expression language ----------------------------------------------------------------------------------------
    # Tokens: strings ('it''s'), numbers, names, and ( ) , . [ ]
    $tokenize = {
        param([string] $Text)
        $tokens = [System.Collections.Generic.List[object]]::new()
        $i = 0
        while ($i -lt $Text.Length) {
            $c = $Text[$i]
            if ([char]::IsWhiteSpace($c)) { $i++; continue }
            if ($c -eq "'") {
                $sb = [System.Text.StringBuilder]::new()
                $i++
                while ($i -lt $Text.Length) {
                    if ($Text[$i] -eq "'") { if ($i + 1 -lt $Text.Length -and $Text[$i + 1] -eq "'") { $null = $sb.Append("'"); $i += 2; continue }; break }
                    $null = $sb.Append($Text[$i]); $i++
                }
                $i++
                $tokens.Add(@{ Kind = 'String'; Value = $sb.ToString() })
                continue
            }
            if ([char]::IsDigit($c) -or ($c -eq '-' -and $i + 1 -lt $Text.Length -and [char]::IsDigit($Text[$i + 1]))) {
                $start = $i; $i++
                while ($i -lt $Text.Length -and [char]::IsDigit($Text[$i])) { $i++ }
                $tokens.Add(@{ Kind = 'Number'; Value = [long]$Text.Substring($start, $i - $start) })
                continue
            }
            if ([char]::IsLetter($c) -or $c -eq '_') {
                $start = $i
                while ($i -lt $Text.Length -and ([char]::IsLetterOrDigit($Text[$i]) -or $Text[$i] -eq '_')) { $i++ }
                $tokens.Add(@{ Kind = 'Name'; Value = $Text.Substring($start, $i - $start) })
                continue
            }
            if ('(),.[]'.Contains($c)) { $tokens.Add(@{ Kind = [string]$c; Value = [string]$c }); $i++; continue }
            throw "Unexpected '$c' in [$Text]."
        }
        , $tokens.ToArray()
    }

    $resolveId = {
        param([object[]] $Arguments, [string] $Prefix)
        # resourceId([subscriptionId], [resourceGroupName], type, name1, name2, ...)
        $typeAt = -1
        for ($j = 0; $j -lt $Arguments.Count; $j++) { if ($Arguments[$j] -is [string] -and $Arguments[$j] -match '^[A-Za-z0-9]+\.[A-Za-z0-9.]+/') { $typeAt = $j; break } }
        if ($typeAt -lt 0) { return $unresolved }
        $type = [string]$Arguments[$typeAt]
        $names = @($Arguments[($typeAt + 1)..($Arguments.Count - 1)] | ForEach-Object { [string]$_ })
        $segments = $type.Split('/')
        $path = "providers/$($segments[0])"
        for ($j = 1; $j -lt $segments.Count; $j++) { $path += "/$($segments[$j])/$(if ($j - 1 -lt $names.Count) { $names[$j - 1] })" }
        if ($Prefix -ne 'resource') { return "$Prefix/$path" }
        $sub = $SubscriptionId; $rg = $Context.ResourceGroup
        if ($typeAt -eq 2) { $sub = [string]$Arguments[0]; $rg = [string]$Arguments[1] }
        elseif ($typeAt -eq 1) { $rg = [string]$Arguments[0] }
        if ($rg) { "/subscriptions/$sub/resourceGroups/$rg/$path" } else { "/subscriptions/$sub/$path" }
    }

    $Context = $null
    $evalExpression = $null
    $evalValue = $null
    $call = {
        param([string] $Name, [object[]] $Arguments)
        $n = $Name.ToLowerInvariant()
        # Functions whose arguments may be unresolved and still answer.
        if ($n -eq 'if') { $test = $Arguments[0]; if (& $isUnresolved $test) { return $unresolved }; if ($test) { return $Arguments[1] } else { return $Arguments[2] } }
        if ($n -eq 'coalesce') { foreach ($a in $Arguments) { if (& $isUnresolved $a) { return $unresolved }; if ($null -ne $a) { return $a } }; return $null }
        foreach ($a in $Arguments) { if (& $isUnresolved $a) { return $unresolved } }
        switch ($n) {
            'parameters' { $key = @($Context.Parameters.Keys | Where-Object { $_ -eq [string]$Arguments[0] }) | Select-Object -First 1; if ($null -ne $key) { return & $parameterOf $key }; return $unresolved }
            'variables' { return & $variableOf ([string]$Arguments[0]) }
            'concat' { if ($Arguments.Count -and $Arguments[0] -is [System.Collections.IList] -and $Arguments[0] -isnot [string]) { return , @(foreach ($a in $Arguments) { @($a) }) }; return (-join @($Arguments | ForEach-Object { [string]$_ })) }
            'format' {
                $text = [string]$Arguments[0]
                $rest = @($Arguments | Select-Object -Skip 1)
                return [regex]::Replace($text, '\{(\d+)(:[^}]*)?\}', { param($m) $k = [int]$m.Groups[1].Value; if ($k -lt $rest.Count) { [string]$rest[$k] } else { $m.Value } })
            }
            'tolower' { return ([string]$Arguments[0]).ToLowerInvariant() }
            'toupper' { return ([string]$Arguments[0]).ToUpperInvariant() }
            'trim' { return ([string]$Arguments[0]).Trim() }
            'replace' { return ([string]$Arguments[0]).Replace([string]$Arguments[1], [string]$Arguments[2]) }
            'substring' { $s = [string]$Arguments[0]; $start = [int]$Arguments[1]; if ($Arguments.Count -gt 2) { return $s.Substring($start, [Math]::Min([int]$Arguments[2], $s.Length - $start)) }; return $s.Substring($start) }
            'take' { $v = $Arguments[0]; $k = [int]$Arguments[1]; if ($v -is [string]) { return $v.Substring(0, [Math]::Min($k, $v.Length)) }; return , @(@($v) | Select-Object -First $k) }
            'skip' { $v = $Arguments[0]; $k = [int]$Arguments[1]; if ($v -is [string]) { return $v.Substring([Math]::Min($k, $v.Length)) }; return , @(@($v) | Select-Object -Skip $k) }
            'split' { return , @(([string]$Arguments[0]).Split([string[]]@($Arguments[1]), [StringSplitOptions]::None)) }
            'join' { return (@($Arguments[0]) -join [string]$Arguments[1]) }
            'first' { $v = $Arguments[0]; if ($v -is [string]) { return $(if ($v) { [string]$v[0] } else { '' }) }; return @($v)[0] }
            'last' { $v = $Arguments[0]; if ($v -is [string]) { return $(if ($v) { [string]$v[-1] } else { '' }) }; return @($v)[-1] }
            'length' { $v = $Arguments[0]; if ($v -is [string]) { return $v.Length }; if ($v -is [System.Collections.IDictionary]) { return $v.Count }; return @($v).Count }
            'empty' { $v = $Arguments[0]; if ($null -eq $v) { return $true }; if ($v -is [string]) { return -not $v }; if ($v -is [System.Collections.IDictionary]) { return -not $v.Count }; return -not @($v).Count }
            'contains' { $v = $Arguments[0]; if ($v -is [string]) { return $v.IndexOf([string]$Arguments[1], [StringComparison]::OrdinalIgnoreCase) -ge 0 }; if ($v -is [System.Collections.IDictionary]) { return (& $has $v ([string]$Arguments[1])) }; return @($v) -contains $Arguments[1] }
            'startswith' { return ([string]$Arguments[0]).StartsWith([string]$Arguments[1], [StringComparison]::OrdinalIgnoreCase) }
            'endswith' { return ([string]$Arguments[0]).EndsWith([string]$Arguments[1], [StringComparison]::OrdinalIgnoreCase) }
            'equals' { if ($Arguments[0] -is [string] -or $Arguments[1] -is [string]) { return [string]$Arguments[0] -ceq [string]$Arguments[1] }; return (ConvertTo-Json -InputObject $Arguments[0] -Compress -Depth 20) -eq (ConvertTo-Json -InputObject $Arguments[1] -Compress -Depth 20) }
            'not' { return -not [bool]$Arguments[0] }
            'and' { return -not @($Arguments | Where-Object { -not [bool]$_ }).Count }
            'or' { return [bool]@($Arguments | Where-Object { [bool]$_ }).Count }
            'greater' { return $Arguments[0] -gt $Arguments[1] }
            'less' { return $Arguments[0] -lt $Arguments[1] }
            'string' { if ($Arguments[0] -is [string]) { return $Arguments[0] }; if ($Arguments[0] -is [bool]) { return $Arguments[0].ToString().ToLowerInvariant() }; if ($Arguments[0] -is [System.Collections.IDictionary] -or $Arguments[0] -is [System.Collections.IList]) { return ConvertTo-Json -InputObject $Arguments[0] -Compress -Depth 20 }; return [string]$Arguments[0] }
            'int' { return [long]$Arguments[0] }
            'bool' { if ($Arguments[0] -is [string]) { return $Arguments[0] -eq 'true' }; return [bool]$Arguments[0] }
            'json' { return ConvertFrom-Json -InputObject ([string]$Arguments[0]) -AsHashtable }
            'true' { return $true }
            'false' { return $false }
            'null' { return $null }
            'array' { return , @($Arguments[0]) }
            'createarray' { return , @($Arguments) }
            'createobject' { $o = [ordered]@{}; for ($j = 0; $j + 1 -lt $Arguments.Count; $j += 2) { $o[[string]$Arguments[$j]] = $Arguments[$j + 1] }; return $o }
            'union' {
                if ($Arguments[0] -is [System.Collections.IDictionary]) { $o = [ordered]@{}; foreach ($a in $Arguments) { foreach ($k in @($a.Keys)) { $o[$k] = $a[$k] } }; return $o }
                return , @($Arguments | ForEach-Object { @($_) } | Select-Object -Unique)
            }
            'copyindex' { return $(if ($Arguments.Count -and $Arguments[-1] -is [long]) { $Arguments[-1] } else { [long]0 }) }
            'resourcegroup' { if (-not $Context.ResourceGroup) { return $unresolved }; return [ordered]@{ name = $Context.ResourceGroup; location = $(if ($Context.Location) { $Context.Location } else { $unresolved }); id = "/subscriptions/$SubscriptionId/resourceGroups/$($Context.ResourceGroup)"; tags = @{}; properties = @{} } }
            'subscription' { return [ordered]@{ subscriptionId = $SubscriptionId; id = "/subscriptions/$SubscriptionId"; tenantId = $unresolved; displayName = $unresolved } }
            'deployment' { return [ordered]@{ name = 'aac-policy-check'; properties = @{} } }
            'resourceid' { return & $resolveId $Arguments 'resource' }
            'subscriptionresourceid' { $a = @($Arguments); $sub = $SubscriptionId; if ($a.Count -and [string]$a[0] -notmatch '/') { $sub = [string]$a[0]; $a = @($a | Select-Object -Skip 1) }; return & $resolveId $a "/subscriptions/$sub" }
            'tenantresourceid' { return & $resolveId $Arguments '' }
            'extensionresourceid' { return & $resolveId @($Arguments | Select-Object -Skip 1) ([string]$Arguments[0]) }
            default { return $unresolved }
        }
    }
    $evalExpression = {
        param([string] $Text)
        $tokens = & $tokenize $Text
        $pos = [ref]0
        $parse = $null
        $parse = {
            $t = $tokens[$pos.Value]
            $value = $null
            if ($t.Kind -eq 'String') { $value = $t.Value; $pos.Value++ }
            elseif ($t.Kind -eq 'Number') { $value = $t.Value; $pos.Value++ }
            elseif ($t.Kind -eq 'Name') {
                $pos.Value++
                $arguments = [System.Collections.Generic.List[object]]::new()
                if ($pos.Value -lt $tokens.Count -and $tokens[$pos.Value].Kind -eq '(') {
                    $pos.Value++
                    while ($tokens[$pos.Value].Kind -ne ')') {
                        $arguments.Add((& $parse))
                        if ($tokens[$pos.Value].Kind -eq ',') { $pos.Value++ }
                    }
                    $pos.Value++
                }
                $value = & $call $t.Value $arguments.ToArray()
            }
            else { throw "Unexpected '$($t.Value)'." }
            # Property and index access.
            while ($pos.Value -lt $tokens.Count -and $tokens[$pos.Value].Kind -in '.', '[') {
                if ($tokens[$pos.Value].Kind -eq '.') {
                    $pos.Value++
                    $member = [string]$tokens[$pos.Value].Value
                    $pos.Value++
                    if (& $isUnresolved $value) { continue }
                    $value = if ($value -is [System.Collections.IDictionary]) { if (& $has $value $member) { & $get $value $member } else { $null } } else { $unresolved }
                }
                else {
                    $pos.Value++
                    $index = & $parse
                    $pos.Value++
                    if ((& $isUnresolved $value) -or (& $isUnresolved $index)) { $value = $unresolved; continue }
                    $value = if ($value -is [System.Collections.IDictionary]) { & $get $value ([string]$index) } elseif ($null -ne $value) { @($value)[[int]$index] } else { $null }
                }
            }
            , $value
        }
        try { $result = & $parse; , $result }
        catch { $unresolved }
    }
    # A value: strings that are [expressions] evaluated, objects and lists
    # walked. Unresolved parts of an object are dropped, their paths kept.
    $evalValue = {
        param($Value, [string] $Path, [System.Collections.Generic.List[string]] $Missing)
        if ($Value -is [string]) {
            if ($Value.StartsWith('[[')) { return $Value.Substring(1) }
            if ($Value.StartsWith('[') -and $Value.EndsWith(']')) {
                $result = & $evalExpression $Value.Substring(1, $Value.Length - 2)
                if (& $isUnresolved $result) { if ($null -ne $Missing) { $Missing.Add($Path) }; return $unresolved }
                return , $result
            }
            return $Value
        }
        if ($Value -is [System.Collections.IDictionary]) {
            $o = [ordered]@{}
            foreach ($k in @($Value.Keys)) {
                $v = & $evalValue $Value[$k] $(if ($Path) { "$Path.$k" } else { [string]$k }) $Missing
                if (-not (& $isUnresolved $v)) { $o[[string]$k] = $v }
            }
            return $o
        }
        if ($Value -is [System.Collections.IList]) {
            $list = [System.Collections.Generic.List[object]]::new()
            for ($j = 0; $j -lt $Value.Count; $j++) {
                $v = & $evalValue $Value[$j] "$Path[$j]" $Missing
                if (-not (& $isUnresolved $v)) { $list.Add($v) }
            }
            return , $list.ToArray()
        }
        , $Value
    }

    # A template's scope: its parameters and variables, each worked out once.
    $newContext = {
        param([System.Collections.IDictionary] $Body, [System.Collections.IDictionary] $Given, [string] $Group, [string] $GroupLocation)
        $declared = & $get $Body 'parameters'
        if ($declared -isnot [System.Collections.IDictionary]) { $declared = @{} }
        $variables = & $get $Body 'variables'
        if ($variables -isnot [System.Collections.IDictionary]) { $variables = @{} }
        @{ Parameters = $declared; Given = $Given; Variables = $variables; ResourceGroup = $Group; Location = $GroupLocation; Values = @{}; VariableValues = @{}; Busy = @{} }
    }
    # Both run with $Context the template whose parameter or variable it is.
    $parameterOf = {
        param([string] $Name)
        if ($Context.Values.Contains($Name)) { return , $Context.Values[$Name] }
        $given = @($Context.Given.Keys | Where-Object { $_ -eq $Name }) | Select-Object -First 1
        $value = if ($null -ne $given) { $Context.Given[$given] }
        elseif (& $has $Context.Parameters[$Name] 'defaultValue') { & $evalValue (& $get $Context.Parameters[$Name] 'defaultValue') '' $null }
        else { $unresolved }
        $Context.Values[$Name] = $value
        , $value
    }
    $variableOf = {
        param([string] $Name)
        $key = @($Context.Variables.Keys | Where-Object { $_ -eq $Name }) | Select-Object -First 1
        if ($null -eq $key) { return $unresolved }
        if ($Context.VariableValues.Contains($key)) { return , $Context.VariableValues[$key] }
        if ($Context.Busy.Contains($key)) { return $unresolved }
        $Context.Busy[$key] = $true
        $value = & $evalValue $Context.Variables[$key] '' $null
        $Context.VariableValues[$key] = $value
        , $value
    }

    $walk = $null
    $walk = {
        param([System.Collections.IDictionary] $Body, $Ctx, [string] $From, [bool] $AtSubscription)
        $saved = $Context
        $Context = $Ctx
        foreach ($item in @(& $resourceList (& $get $Body 'resources'))) { & $visit $item '' '' $From $AtSubscription }
        $Context = $saved
    }
    $visit = $null
    $visit = {
        param($Item, [string] $ParentType, [string] $ParentName, [string] $From, [bool] $AtSubscription)
        if ($Item -isnot [System.Collections.IDictionary]) { return }
        if ([bool](& $get $Item 'existing')) { return }
        $missing = [System.Collections.Generic.List[string]]::new()
        if (& $has $Item 'condition') {
            $condition = & $evalValue (& $get $Item 'condition') 'condition' $null
            if ($condition -is [bool] -and -not $condition) { return }
        }
        $type = [string](& $get $Item 'type')
        if ($ParentType -and $type -notmatch '/') { $type = "$ParentType/$type" }
        $nameValue = & $evalValue (& $get $Item 'name') 'name' $missing
        $name = [string]$nameValue
        if (& $isUnresolved $nameValue) {
            # Numbered, so two resources named at deployment keep apart.
            $unnamed.Count++
            $name = if ($unnamed.Count -eq 1) { 'unresolved-name' } else { "unresolved-name-$($unnamed.Count)" }
        }
        if ($ParentName -and (@($name -split '/').Count -lt @($type -split '/').Count - 1)) { $name = "$ParentName/$name" }
        $copy = & $has $Item 'copy'

        if ($type -ieq 'Microsoft.Resources/deployments') {
            $properties = & $get $Item 'properties'
            $inner = & $get $properties 'template'
            if ($inner -isnot [System.Collections.IDictionary]) {
                if (& $has $properties 'templateLink') { $notices.Add("Module '$name' links its template by URI - it isn't fetched, so its resources aren't checked.") }
                return
            }
            $group = $Context.ResourceGroup
            $groupLocation = $Context.Location
            $rgValue = & $evalValue (& $get $Item 'resourceGroup') '' $null
            if ($rgValue -is [string] -and $rgValue -and $rgValue -ne $group) { $group = $rgValue; $groupLocation = '' }
            $scope = [string](& $get (& $get $properties 'expressionEvaluationOptions') 'scope')
            if ($scope -ieq 'inner') {
                $given = @{}
                $passed = & $get $properties 'parameters'
                if ($passed -is [System.Collections.IDictionary]) {
                    foreach ($k in @($passed.Keys)) {
                        $v = & $evalValue (& $get $passed[$k] 'value') '' $null
                        if (-not (& $isUnresolved $v)) { $given[$k] = $v }
                    }
                }
                & $walk $inner (& $newContext $inner $given $group $groupLocation) "module $name" ($AtSubscription -and -not $group)
            }
            else {
                $outer = $Context.Clone()
                $outer.ResourceGroup = $group
                $outer.Location = $groupLocation
                & $walk $inner $outer "module $name" ($AtSubscription -and -not $group)
            }
            return
        }

        $content = [ordered]@{ type = $type; name = ($name -split '/')[-1] }
        foreach ($key in 'location', 'tags', 'sku', 'kind', 'identity', 'zones', 'plan', 'extendedLocation', 'properties') {
            if (-not (& $has $Item $key)) { continue }
            $v = & $evalValue (& $get $Item $key) $key $missing
            if (-not (& $isUnresolved $v)) { $content[$key] = $v }
        }
        # A name only known at deployment (uniqueString) isn't sent: a naming
        # policy would judge the placeholder.
        if ($missing -contains 'name') { $content.Remove('name') }
        $segments = $type.Split('/')
        $names = $name.Split('/')
        $path = "providers/$($segments[0])"
        $parentPath = ''
        for ($j = 1; $j -lt $segments.Count; $j++) {
            if ($j -eq $segments.Count - 1) { $parentPath = $path }
            $path += "/$($segments[$j])/$(if ($j - 1 -lt $names.Count) { $names[$j - 1] })"
        }
        $scopeId = if ($Context.ResourceGroup -and -not ($AtSubscription -and $type -ieq 'Microsoft.Resources/resourceGroups')) { "/subscriptions/$SubscriptionId/resourceGroups/$($Context.ResourceGroup)" } else { "/subscriptions/$SubscriptionId" }
        $id = if ($type -ieq 'Microsoft.Resources/resourceGroups') { "/subscriptions/$SubscriptionId/resourceGroups/$name" } else { "$scopeId/$path" }
        $parentId = if ($segments.Count -gt 2) { "$scopeId/$parentPath" } else { '' }
        $extension = & $evalValue (& $get $Item 'scope') 'scope' $null
        if ($extension -is [string] -and $extension) {
            $parentId = $extension
            $id = "$($extension.TrimEnd('/'))/$path"
        }
        $resources.Add(@{
                Type = $type; Name = $name; Id = $id; ParentId = $parentId; ScopeId = $scopeId; ResourceGroup = $Context.ResourceGroup
                ApiVersion = [string](& $get $Item 'apiVersion'); Location = $(if ($content.Contains('location')) { [string]$content['location'] } else { '' })
                Tags = $(if ($content['tags'] -is [System.Collections.IDictionary]) { $content['tags'] } else { @{} }); Kind = $(if ($content.Contains('kind')) { [string]$content['kind'] } else { '' })
                Content = $content; Unresolved = $missing.ToArray(); Source = $From; Copy = $copy
            })
        foreach ($child in @(& $resourceList (& $get $Item 'resources'))) { & $visit $child $type $name $From $AtSubscription }
    }

    $schema = [string](& $get $Template '$schema')
    $atSubscription = $schema -match '(?i)subscriptionDeploymentTemplate' -or -not $ResourceGroupName
    if ($schema -match '(?i)(managementGroup|tenant)DeploymentTemplate') { $notices.Add('A management-group or tenant template: its resources are checked against the subscription given.') }
    $root = & $newContext $Template $Parameter $(if ($schema -match '(?i)subscriptionDeploymentTemplate') { '' } else { $ResourceGroupName }) $Location
    $Context = $root
    foreach ($p in @($root.Parameters.Keys)) { if (& $isUnresolved (& $parameterOf $p)) { $notices.Add("Parameter '$p' has no value or default: what depends on it isn't checked. Give it with -ParameterPath or -Parameter.") } }
    & $walk $Template $root $Source $atSubscription
    @{ Resources = $resources.ToArray(); Notices = $notices.ToArray() }
}
