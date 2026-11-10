function Show-AACResourceChart {
    <#
    .SYNOPSIS
        Counts the resources by type, location, resource group or subscription
        and draws them as a bar chart - or, with -HtmlFullPath, writes the
        interactive inventory - for Get-AACInventory -View Chart (and the
        deprecated Show-AACResource).
    .DESCRIPTION
        Two Resource Graph queries however many resources there are (three with
        -HtmlFullPath). Returns the counts (AAC.ResourceCount) with -PassThru.
        -HtmlFullPath is already resolved by the caller.
    #>
    [CmdletBinding()]
    [OutputType('AAC.ResourceCount')]
    param(
        [string[]] $SubscriptionId,

        [ValidateSet('Type', 'Location', 'ResourceGroup', 'Subscription')]
        [string] $By = 'Type',

        [string[]] $ResourceType,

        [int] $Top = 20,

        [string] $HtmlFullPath,

        [string] $Title = 'Azure resources',

        [switch] $NoPaging,

        [switch] $PassThru
    )
    # Signed in? (Get-AACAccessToken says what to do when not.)
    $null = Get-AACAccessToken

    # Wildcards -> one KQL regular expression over the lower-case type.
    $filter = if ($ResourceType) {
        $patterns = @($ResourceType | ForEach-Object { '^' + ([regex]::Escape($_.ToLowerInvariant()) -replace '\\\*', '.*') + '$' })
        "| where tolower(type) matches regex @'$($patterns -join '|')'"
    }
    $groupBy = @{
        Type          = 'name = tolower(type)'
        Location      = 'name = tolower(location)'
        ResourceGroup = 'subscriptionId, name = tolower(resourceGroup)'
        Subscription  = 'name = subscriptionId'
    }[$By]

    # The title first, then a line per step - as every command shows them.
    Write-AACRule -Title 'Azure Admin Console :: Azure resources' -Color 'deepskyblue3_1'
    $data = Invoke-AACProgress -ScriptBlock {
        # The queries at once (Invoke-AACGraphBatch); subscription names
        # tenant-wide, and - for the HTML inventory - the resources themselves.
        $queries = [ordered]@{
            counts        = "Resources $filter | summarize n = count() by $groupBy"
            totals        = "Resources $filter | summarize resources = count(), types = dcount(tolower(type)), locations = dcount(tolower(location)), groups = dcount(strcat(subscriptionId, '/', tolower(resourceGroup))), subscriptions = dcount(subscriptionId)"
            subscriptions = @{ Tenant = $true; Query = "resourcecontainers | where type =~ 'microsoft.resources/subscriptions' | project subscriptionId, name" }
        }
        if ($HtmlFullPath) {
            $queries['inventory'] = "Resources $filter | project id, name, type = tolower(type), location = tolower(location), resourceGroup, subscriptionId, kind, sku = tostring(sku.name), tags = tostring(tags) | order by name asc"
        }
        Update-AACProgress -Id 'read' -Total $queries.Count -Description 'Counting resources in Azure Resource Graph'
        $batch = Invoke-AACGraphBatch -AsObject -SubscriptionId $SubscriptionId -Query $queries -OnProgress { param($Name, $Done, $Total) Update-AACProgress -Id 'read' -Increment 1 -Description "Read the $Name ($Done of $Total queries)" }
        $countRows = @($batch.Rows['counts'])
        $totalRows = @($batch.Rows['totals'])
        $subscriptionRows = @($batch.Rows['subscriptions'])
        $inventoryRows = @(if ($HtmlFullPath) { $batch.Rows['inventory'] })
        $resourceTotal = 0
        foreach ($row in $countRows) { $resourceTotal += [int]$row.n }
        Update-AACProgress -Id 'read' -Complete -Description ('Counted {0:N0} resource(s) in {1:N0} group(s) by {2}' -f $resourceTotal, $countRows.Count, $By.ToLowerInvariant())
        @{ Counts = $countRows; Totals = $totalRows; Subscriptions = $subscriptionRows; Inventory = $inventoryRows }
    }

    $subscriptionNames = @{}
    foreach ($subscription in $data.Subscriptions) {
        $subscriptionNames[$subscription.subscriptionId] = $subscription.name
    }
    $label = {
        param($Row)
        switch ($By) {
            'Type' { ([string]$Row.name) -replace '^microsoft\.', '' }
            'Location' { if ($Row.name) { [string]$Row.name } else { '(none)' } }
            'ResourceGroup' { "$($Row.name) ($(if ($subscriptionNames[$Row.subscriptionId]) { $subscriptionNames[$Row.subscriptionId] } else { $Row.subscriptionId }))" }
            'Subscription' { if ($subscriptionNames[[string]$Row.name]) { $subscriptionNames[[string]$Row.name] } else { [string]$Row.name } }
        }
    }

    # Measure-Object returns nothing at all for an empty list, so add up by hand.
    $total = 0.0
    foreach ($row in $data.Counts) { $total += [double]$row.n }
    $counts = @($data.Counts | Sort-Object -Property @{ Expression = { [int]$_.n }; Descending = $true }, name | ForEach-Object {
            [pscustomobject]@{
                PSTypeName = 'AAC.ResourceCount'
                By         = $By
                Name       = & $label $_
                Count      = [int]$_.n
                Share      = if ($total) { [Math]::Round(100 * $_.n / $total, 1) } else { 0 }
            }
        })

    # --- The HTML inventory, or the view ----------------------------------------------------
    if ($HtmlFullPath) {
        $inventory = @(foreach ($row in $data.Inventory) {
                $tags = ''
                if ($row.tags -and $row.tags -ne '{}' -and $row.tags -ne 'null') {
                    try {
                        $parsed = ConvertFrom-Json -InputObject $row.tags -AsHashtable -ErrorAction Stop
                        $tags = (@($parsed.Keys | Sort-Object | ForEach-Object { "$_=$($parsed[$_])" }) -join '; ')
                    }
                    catch { $tags = [string]$row.tags }
                }
                [pscustomobject]@{
                    Name             = [string]$row.name
                    Type             = [string]$row.type
                    ResourceGroup    = [string]$row.resourceGroup
                    Location         = [string]$row.location
                    SubscriptionName = $(if ($subscriptionNames[$row.subscriptionId]) { $subscriptionNames[$row.subscriptionId] } else { [string]$row.subscriptionId })
                    SubscriptionId   = [string]$row.subscriptionId
                    Kind             = [string]$row.kind
                    Sku              = [string]$row.sku
                    Tags             = $tags
                    ResourceId       = [string]$row.id
                }
            })
        $scope = [ordered]@{ Subscriptions = if ($SubscriptionId) { $SubscriptionId -join ', ' } else { 'every subscription the account can see' } }
        if ($ResourceType) { $scope['Resource types'] = $ResourceType -join ', ' }
        $null = Invoke-AACExport -HtmlPath $HtmlFullPath -WriteHtml {
            Write-AACResourceHtml -Resource $inventory -Path $HtmlFullPath -Title $Title -Detail $scope
        }
    }
    else {
        Invoke-AACPagedOutput -NoPaging:$NoPaging -ScriptBlock {
            $escape = { param($Text) [Spectre.Console.Markup]::Escape([string]$Text) }
            # Unicode symbols, or ASCII in a console that isn't UTF-8.
            $glyph = Get-AACGlyph
            $facts = [System.Collections.Generic.List[string]]::new()
            if ($script:AACSession) {
                $facts.Add("[white]$(& $escape $script:AACSession.Account)[/]")
                $facts.Add("tenant $(& $escape $script:AACSession.TenantId)")
            }
            $facts.Add($(if ($SubscriptionId) { "$($SubscriptionId.Count) subscription(s)" } else { 'all subscriptions' }))
            if ($ResourceType) { $facts.Add("types: $(& $escape ($ResourceType -join ', '))") }
            $facts.Add((Get-Date).ToString('d MMM yyyy HH:mm'))
            Write-AACMarkup "[grey58]$($facts -join " $($glyph.Dot) ")[/]"
            [Spectre.Console.AnsiConsole]::WriteLine()

            if ($counts.Count -eq 0) {
                Show-AACCallout Info -Message '[bold]No resources[/] [grey58]were found for this account and these filters.[/]'
            }
            else {
                $totals = $data.Totals | Select-Object -First 1
                Show-AACTileRow -Tile @(
                    @{ Value = '{0:N0}' -f [int]$totals.resources; Caption = 'resources'; Color = 'deepskyblue1' }
                    @{ Value = '{0:N0}' -f [int]$totals.types; Caption = 'resource types'; Color = 'mediumpurple2' }
                    @{ Value = '{0:N0}' -f [int]$totals.subscriptions; Caption = 'subscriptions'; Color = 'springgreen2' }
                    @{ Value = '{0:N0}' -f [int]$totals.groups; Caption = 'resource groups'; Color = 'gold1' }
                    @{ Value = '{0:N0}' -f [int]$totals.locations; Caption = 'locations'; Color = 'hotpink' }
                )
                [Spectre.Console.AnsiConsole]::WriteLine()

                $noun = @{ Type = 'type'; Location = 'location'; ResourceGroup = 'resource group'; Subscription = 'subscription' }[$By]
                $bars = @($counts | Select-Object -First $Top | ForEach-Object { @{ Label = $_.Name; Value = $_.Count } })
                $rest = @($counts | Select-Object -Skip $Top)
                if ($rest.Count -gt 0) {
                    $bars += @{ Label = "$($rest.Count) other $noun$(if ($rest.Count -ne 1) { 's' })"; Value = ($rest | Measure-Object -Property Count -Sum).Sum; Color = 'grey50' }
                }
                $chartTitle = "Resources by $noun$(if ($counts.Count -gt $Top) { " (top $Top of $($counts.Count))" })"
                Show-AACBarChart -Item $bars -Title $chartTitle
                [Spectre.Console.AnsiConsole]::WriteLine()
                Write-AACMarkup '[grey42]-By Type|Location|ResourceGroup|Subscription picks what is counted; -PassThru returns the counts.[/]'
            }
        }
    }

    if ($PassThru) {
        $counts
    }
}
