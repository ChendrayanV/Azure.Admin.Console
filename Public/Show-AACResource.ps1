function Show-AACResource {
    <#
    .SYNOPSIS
        Shows how many Azure resources you have - by type, location, resource
        group or subscription - as a colourful Spectre.Console bar chart.
    .DESCRIPTION
        Counts every resource the signed-in account can see (or only those in
        -SubscriptionId, of -ResourceType) with Azure Resource Graph, over
        REST with the Connect-AAC sign-in - two queries however many
        resources there are, and no Az modules.

        The view:
          ── Azure Admin Console :: Azure resources ─────────────────────
          account · tenant · scope · when
          [ resources ] [ types ] [ subscriptions ] [ resource groups ] [ locations ]

          Resources by type (top 20)
          compute/virtualmachines       ████████████████████████ 412
          network/networkinterfaces     ███████████████████ 398
          storage/storageaccounts       ██████████ 164
          ...
          37 other types                ████ 61

        Each bar has its own colour. -By picks what is counted: resource
        Type (the default), Location, ResourceGroup or Subscription. -Top
        sets how many bars are drawn; the rest are summed in a final grey
        bar.

        With -PassThru the counts are also returned as AAC.ResourceCount
        objects (Name, Count, Share), every one of them, not only the top.
    .PARAMETER SubscriptionId
        Only count resources in these subscriptions. Defaults to every
        subscription the signed-in account can see.
    .PARAMETER By
        What to count by: Type (default), Location, ResourceGroup or
        Subscription.
    .PARAMETER ResourceType
        Only count resources of these types. Case-insensitive; wildcards
        work, e.g. 'microsoft.network/*'.
    .PARAMETER Top
        How many bars to draw (default 20); the rest are summed in one bar.
    .PARAMETER PassThru
        Also return the counts as AAC.ResourceCount objects.
    .EXAMPLE
        Connect-AAC
        Show-AACResource
        The top 20 resource types across every subscription you can see.
    .EXAMPLE
        Show-AACResource -By Location
        How many resources are in each Azure region.
    .EXAMPLE
        Show-AACResource -ResourceType 'microsoft.network/*' -Top 10
        The ten most common networking resource types.
    .EXAMPLE
        Show-AACResource -By Subscription -PassThru | Export-Csv .\ResourcesPerSubscription.csv -NoTypeInformation
        Shows resources per subscription and saves the counts as a CSV file.
    .OUTPUTS
        AAC.ResourceCount (with -PassThru)
    #>
    [CmdletBinding()]
    [OutputType('AAC.ResourceCount')]
    param(
        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [ValidateSet('Type', 'Location', 'ResourceGroup', 'Subscription')]
        [string] $By = 'Type',

        # Letters, digits, '.', '/', '-', '_' and '*' only: the patterns go
        # into a Resource Graph query.
        [ValidatePattern('^[\w.*/-]+$')]
        [SupportsWildcards()]
        [string[]] $ResourceType,

        [ValidateRange(1, 100)]
        [int] $Top = 20,

        [switch] $PassThru
    )

    $headers = @{ Authorization = "Bearer $(Get-AACAccessToken)" }

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
        Update-AACProgress -Id 'read' -Total 3 -Description 'Counting resources in Azure Resource Graph'
        $countRows = @(Invoke-AACResourceGraphQuery -SubscriptionId $SubscriptionId -Headers $headers -Query "Resources $filter | summarize n = count() by $groupBy")
        Update-AACProgress -Id 'read' -Increment 1 -Description 'Counting types, locations and resource groups'
        $totalRows = @(Invoke-AACResourceGraphQuery -SubscriptionId $SubscriptionId -Headers $headers -Query "Resources $filter | summarize resources = count(), types = dcount(tolower(type)), locations = dcount(tolower(location)), groups = dcount(strcat(subscriptionId, '/', tolower(resourceGroup))), subscriptions = dcount(subscriptionId)")
        Update-AACProgress -Id 'read' -Increment 1 -Description 'Reading subscription names'
        $subscriptionRows = @(Invoke-AACResourceGraphQuery -Headers $headers -Query "resourcecontainers | where type =~ 'microsoft.resources/subscriptions' | project subscriptionId, name")
        $resourceTotal = 0
        foreach ($row in $countRows) { $resourceTotal += [int]$row.n }
        Update-AACProgress -Id 'read' -Complete -Description ('Counted {0:N0} resource(s) in {1:N0} group(s) by {2}' -f $resourceTotal, $countRows.Count, $By.ToLowerInvariant())
        @{ Counts = $countRows; Totals = $totalRows; Subscriptions = $subscriptionRows }
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

    # --- The view ------------------------------------------------------------------------
    $escape = { param($Text) [Spectre.Console.Markup]::Escape([string]$Text) }
    # Unicode symbols, or ASCII in a console that isn't UTF-8.
    $glyph = Get-AACGlyph
    $facts = [System.Collections.Generic.List[string]]::new()
    if ($global:AACSession) {
        $facts.Add("[white]$(& $escape $global:AACSession.Account)[/]")
        $facts.Add("tenant $(& $escape $global:AACSession.TenantId)")
    }
    $facts.Add($(if ($SubscriptionId) { "$($SubscriptionId.Count) subscription(s)" } else { 'all subscriptions' }))
    if ($ResourceType) { $facts.Add("types: $(& $escape ($ResourceType -join ', '))") }
    $facts.Add((Get-Date).ToString('d MMM yyyy HH:mm'))
    Write-AACMarkup "[grey58]$($facts -join " $($glyph.Dot) ")[/]"
    [Spectre.Console.AnsiConsole]::WriteLine()

    if ($counts.Count -eq 0) {
        Show-AACPanel -Content '[bold]No resources[/] [grey58]were found for this account and these filters.[/]' -BorderColor 'grey50' -AllowMarkup
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
        $title = "Resources by $noun$(if ($counts.Count -gt $Top) { " (top $Top of $($counts.Count))" })"
        Show-AACBarChart -Item $bars -Title $title
        [Spectre.Console.AnsiConsole]::WriteLine()
        Write-AACMarkup '[grey42]-By Type|Location|ResourceGroup|Subscription picks what is counted; -PassThru returns the counts.[/]'
    }

    if ($PassThru) {
        $counts
    }
}
