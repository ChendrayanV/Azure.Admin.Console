function Get-AACAssessmentQuery {
    <#
    .SYNOPSIS
        Builds the Resource Graph query of one Invoke-AACAssessment sheet
        (Get-AACAssessmentCatalog) - or the scope filter every resource
        query shares.
    .DESCRIPTION
        -Sheet: returns @{ Query; Columns } - Columns maps each label to
        its spec and the query column it comes back in (c0, c1, ... for KQL
        values; r0, r1, ... for the raw arrays a PowerShell transform turns
        into text; nothing for 'x:' columns filled in later). The query:
          <table> | where type in~ (...) <Where> <scope filter> <Pre>
          | project id, name, resourceGroup, subscriptionId, location, c0 = ..., [tags]

        -Filter alone: returns the scope filter - resource groups (in~,
        any case) and a tag (its key and/or value, any case, the way ARI
        matches them) - for the other resource queries.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Sheet')]
    [OutputType([hashtable], [string])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Sheet')]
        [hashtable] $Sheet,

        [string[]] $ResourceGroupName,

        [string] $TagKey,

        [string] $TagValue,

        [Parameter(ParameterSetName = 'Sheet')]
        [switch] $IncludeTag,

        [Parameter(Mandatory, ParameterSetName = 'Filter')]
        [switch] $Filter
    )

    $quote = { param([string] $Text) "'" + ($Text -replace '\\', '\\' -replace "'", "\'") + "'" }
    $scope = [System.Text.StringBuilder]::new()
    $groups = @($ResourceGroupName | Where-Object { $_ })
    if ($groups.Count) {
        [void]$scope.Append(" | where resourceGroup in~ ($((@($groups | ForEach-Object { & $quote $_ })) -join ', '))")
    }
    if ($TagKey -or $TagValue) {
        # A copy of the tags, one per row, so the tags themselves stay whole.
        [void]$scope.Append(' | where isnotempty(tags) | extend aacTag = tags | mv-expand aacTag | extend aacTagKey = tostring(bag_keys(aacTag)[0])')
        $conditions = @(
            if ($TagKey) { "aacTagKey =~ $(& $quote $TagKey)" }
            if ($TagValue) { "tostring(aacTag[aacTagKey]) =~ $(& $quote $TagValue)" }
        )
        [void]$scope.Append(" | where $($conditions -join ' and ') | project-away aacTag, aacTagKey")
    }
    if ($Filter) { return $scope.ToString() }

    # A property named like a KQL keyword (pool.count) is a ParserFailure in
    # Resource Graph: it's written pool['count'] instead - outside quotes.
    $keywords = 'count|type|kind|title|default|filter|set|range|top|take|limit|order|sort|by|on|in|as|to|of|and|or|not|has|let|with|from|step|print|search|find|parse|sample|distinct|union|join|extend|project|summarize|where|render|contains|between'
    $safe = {
        param([string] $Expression)
        $parts = [regex]::Split($Expression, '(@?''(?:[^''\\]|\\.)*''|@?"(?:[^"\\]|\\.)*")')
        (@(for ($i = 0; $i -lt $parts.Count; $i++) {
                if ($i % 2) { $parts[$i] } else { [regex]::Replace($parts[$i], "(?<=[A-Za-z0-9_\]])\.($keywords)\b", { param($m) "['$($m.Groups[1].Value)']" }) }
            })) -join ''
    }

    $types = @($Sheet.Type | ForEach-Object { ([string]$_).ToLowerInvariant() })
    $table = if ($Sheet.Contains('Table') -and $Sheet.Table) { $Sheet.Table } else { 'resources' }
    $columns = [ordered]@{}
    $projection = [System.Collections.Generic.List[string]]::new()
    $index = 0
    foreach ($label in $Sheet.Columns.Keys) {
        $spec = [string]$Sheet.Columns[$label]
        $entry = @{ Spec = $spec; Column = '' }
        if ($spec -like 'x:*') { $columns[$label] = $entry; continue }
        if ($spec -like '@*') {
            # An array or object, as is: a PowerShell transform makes it text.
            $path = ($spec -replace '^@[a-z]+:', '') -replace '\|.*$', ''
            $entry.Column = "r$index"
            $projection.Add("r$index = $(& $safe $path)")
        }
        else {
            $expression = switch -Regex ($spec) {
                '^kql:(.+)$' { $Matches[1]; break }
                '^int:(.+)$' { "toint($($Matches[1]))"; break }
                '^num:(.+)$' { "round(todouble($($Matches[1])), 2)"; break }
                '^gb:(.+)$' { "round(todouble($($Matches[1])) / 1073741824, 2)"; break }
                '^len:(.+)$' { "array_length($($Matches[1]))"; break }
                '^join:(.+)$' { "strcat_array($($Matches[1]), ', ')"; break }
                '^leaf:(.+)$' { "extract(@'[^/]+`$', 0, tostring($($Matches[1])))"; break }
                '^vnet:(.+)$' { "extract(@'(?i)/virtualnetworks/([^/]+)', 1, tostring($($Matches[1])))"; break }
                '^subnet:(.+)$' { "extract(@'(?i)/subnets/([^/]+)', 1, tostring($($Matches[1])))"; break }
                '^date:(.+)$' { "tostring($($Matches[1]))"; break }
                default { "tostring($spec)" }
            }
            $entry.Column = "c$index"
            $projection.Add("c$index = $(& $safe $expression)")
        }
        $columns[$label] = $entry
        $index++
    }

    $query = [System.Text.StringBuilder]::new($table)
    if ($types.Count -eq 1) { [void]$query.Append(" | where type =~ $(& $quote $types[0])") }
    else { [void]$query.Append(" | where type in~ ($((@($types | ForEach-Object { & $quote $_ })) -join ', '))") }
    if ($Sheet.Contains('Where') -and $Sheet.Where) { [void]$query.Append(" $($Sheet.Where)") }
    [void]$query.Append($scope.ToString())
    if ($Sheet.Contains('Pre') -and $Sheet.Pre) { [void]$query.Append(" $(& $safe $Sheet.Pre)") }
    $tagColumn = if ($IncludeTag) { ', tags' } else { '' }
    [void]$query.Append(" | project id, name, resourceGroup, subscriptionId, location$(if ($projection.Count) { ', ' + ($projection -join ', ') })$tagColumn")
    @{ Query = $query.ToString(); Columns = $columns }
}
