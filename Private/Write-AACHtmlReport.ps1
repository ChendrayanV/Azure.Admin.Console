function Write-AACHtmlReport {
    <#
    .SYNOPSIS
        Writes a single, self-contained, interactive HTML report - the
        -HtmlPath export of Get-AACAdvisorRecommendation, Get-AACFirewallRule,
        Show-AACResource and Show-AACCost.
    .DESCRIPTION
        One file with no external scripts, styles or fonts (Private\
        DataReport.html with the data embedded as JSON), so it opens offline,
        from an e-mail or a pipeline artifact. Each command describes its
        report; the page makes it interactive:

          -Tile     @{ Value; Label; Tone; Table; Filters = @{ Column = 'Value' } }
                    Tone is good, bad, warn, info, violet or neutral. With
                    Table (and Filters), clicking the tile filters that table.
          -Chart    @{ Title; Kind ('bar', the default, or 'donut': each item's
                    share, the total in the middle - CenterLabel under it);
                    Items = @(@{ Label; Value; Display; Tone; Filter });
                       Format = 'N0'|'N2'; Suffix; Table; Column; BaseFilters;
                       Wide }
                    Horizontal bars; with Table and Column, clicking a bar
                    filters the table to Column = the bar's Filter (or Label),
                    plus BaseFilters (@{ Column = 'Value' }) if given.
          -Table    @{ Id; Title; Note; Noun; File; Rows; Columns; Sort =
                       @{ Key; Desc }; GroupBy = @('Column', ...); Group;
                       Filters = @{ Column = 'Value' } (what it opens with);
                       PageSize }
                    Columns: @{ Key; Label; Type; Facet; Hidden; Tones;
                    Format; Sum; CurrencyKey; IdKey; Href; Text; Soon }.
                    Types: text (default), wide (long text, clamped), mono,
                    number, money, score (0-100 as a percentage: 70+
                    green, 40-69 amber, under 40 red), date (Soon: red within 90 days, orange
                    within 180), datetime (date and time, local), badge (Tones = @{ Value = 'bad' }), link
                    (https only), resource (the name with Azure portal and
                    copy-ID buttons from the IdKey column, ResourceId by
                    default). Facet columns get a filter drop-down; Sum
                    columns are totalled for the rows shown and per group.
          -Notice   @{ Tone; Text } lines under the tiles.
          -Tree     @{ Title; OpenTo = 's'; Root = node } a collapsible,
                    searchable hierarchy above the tables. Node: @{ l = 't'|
                    'm'|'s'|'g'|'r'|'d' (tenant, management group,
                    subscription, resource group, resource, deleted
                    resources); n = name; d = detail;
                    c = @(@(count, 'noun'), ...); f = @{ table; filters }
                    (clicking the name filters that table); k = children;
                    x = flagged (e.g. an empty resource group); p = a 0-100
                    score, drawn as a coloured pill; h, m, lo = high,
                    medium and low findings, as red, amber and blue pills;
                    co = a cost, drawn as a green pill (amber with cx), with
                    ct as its tooltip }. Children
                    are drawn when a node is opened, so big trees stay fast.

        Every table can be searched, filtered, sorted (click a header),
        grouped (with subtotals) and downloaded as CSV - the rows shown, all
        of them. Light and dark themes follow the browser, with a switch.
        Rows are shown 200 at a time, so large tables stay fast.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Title,

        [string] $Subtitle,

        [System.Collections.IDictionary] $Fact,

        [object[]] $Tile = @(),

        [object[]] $Chart = @(),

        [object[]] $Table = @(),

        [object[]] $Notice = @(),

        [System.Collections.IDictionary] $Tree
    )

    $fullPath = $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)

    # Keys in camelCase for the page; everything else passes through.
    $camel = {
        param([System.Collections.IDictionary] $Source)
        $out = [ordered]@{}
        foreach ($key in $Source.Keys) {
            $name = [string]$key
            $out[$name.Substring(0, 1).ToLowerInvariant() + $name.Substring(1)] = $Source[$key]
        }
        $out
    }

    $session = $script:AACSession
    $facts = [System.Collections.Generic.List[object]]::new()
    if ($session) {
        $facts.Add([ordered]@{ k = 'Azure account'; v = [string]$session.Account })
        $facts.Add([ordered]@{ k = 'Tenant'; v = [string]$session.TenantId })
    }
    if ($Fact) {
        foreach ($key in $Fact.Keys) { $facts.Add([ordered]@{ k = [string]$key; v = [string]$Fact[$key] }) }
    }
    $facts.Add([ordered]@{ k = 'Computer'; v = "$([Environment]::MachineName) · PowerShell $($PSVersionTable.PSVersion)" })

    $tables = foreach ($item in $Table) {
        $t = & $camel $item
        $t['columns'] = @(foreach ($column in @($item.Columns)) { & $camel $column })
        # Rows: only the columns' properties, as plain values.
        $keys = @($t['columns'] | ForEach-Object { $_['key'] })
        $idKeys = @($t['columns'] | ForEach-Object { $_['idKey'], $_['href'], $_['currencyKey'] } | Where-Object { $_ })
        $keys = @($keys + $idKeys + 'ResourceId' | Select-Object -Unique)
        $t['rows'] = @(foreach ($row in @($item.Rows)) {
                $plain = [ordered]@{}
                foreach ($key in $keys) {
                    $value = if ($row -is [System.Collections.IDictionary]) { $row[$key] } else { Get-AACPropertyValue -InputObject $row -Name $key }
                    if ($value -is [datetime]) { $value = $value.ToString('o', [cultureinfo]::InvariantCulture) }
                    elseif ($null -ne $value -and $value -isnot [string] -and $value -isnot [ValueType]) { $value = [string]$value }
                    $plain[$key] = $value
                }
                $plain
            })
        if ($item.Contains('Sort')) { $t['sort'] = & $camel $item.Sort }
        $t
    }

    $moduleInfo = $MyInvocation.MyCommand.Module
    $model = [ordered]@{
        title         = $Title
        subtitle      = $Subtitle
        generated     = [datetime]::UtcNow.ToString('o', [cultureinfo]::InvariantCulture)
        account       = if ($session) { [string]$session.Account } else { '' }
        tenantId      = if ($session) { [string]$session.TenantId } else { '' }
        moduleVersion = if ($moduleInfo) { "v$($moduleInfo.Version)" } else { '' }
        environment   = "PowerShell $($PSVersionTable.PSVersion)"
        facts         = $facts.ToArray()
        notices       = @(foreach ($item in $Notice) { & $camel $item })
        tiles         = @(foreach ($item in $Tile) { & $camel $item })
        charts        = @(foreach ($item in $Chart) {
                $c = & $camel $item
                $c['items'] = @(foreach ($bar in @($item.Items)) { & $camel $bar })
                $c
            })
        tables        = @($tables)
    }
    if ($Tree) {
        $model['tree'] = [ordered]@{ title = $Tree.Title; openTo = $(if ($Tree.Contains('OpenTo')) { $Tree.OpenTo } else { 's' }); root = $Tree.Root }
    }

    # EscapeHtml turns < > & ' into \u escapes, so no value can close the
    # <script> element the data sits in.
    $json = ConvertTo-Json -InputObject $model -Depth 40 -Compress -EscapeHandling EscapeHtml
    $template = [System.IO.File]::ReadAllText((Join-Path -Path $script:AACModuleRoot -ChildPath 'Private/DataReport.html'))
    $html = $template.Replace('__AAC_TITLE__', [System.Net.WebUtility]::HtmlEncode($Title)).Replace('__AAC_DATA__', $json)

    $folder = Split-Path -Path $fullPath -Parent
    if ($folder -and -not (Test-Path -LiteralPath $folder)) {
        New-Item -ItemType Directory -Path $folder -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($fullPath, $html, [System.Text.UTF8Encoding]::new($false))
    Get-Item -LiteralPath $fullPath
}
