function Show-AACCost {
    <#
    .SYNOPSIS
        Shows what your Azure subscriptions cost - month to date and the
        last few months - as colourful Spectre.Console charts, with optional
        CSV and PDF exports of the detail.
    .DESCRIPTION
        Asks the Azure Cost Management Query API, over REST with the
        Connect-AAC sign-in (no Az modules), for each subscription's actual
        cost over the last -Months months (this month so far included),
        broken down by month, service and resource group - one query per
        subscription. The view:

          ── Azure Admin Console :: Azure cost ──────────────────────────
          account · tenant · subscriptions · period · when
          [ month to date ] [ last month ] [ period total ] [ subscriptions ] [ top service ]

          Month to date by subscription   (when there is more than one)
          Month to date by service        (one bar split by service)
          Month to date by resource group (top 10)
          Last N months                   (one bar per month)
          Actual cost by subscription and month - with a total column and,
          for several subscriptions, a total row

        Amounts are in each subscription's billing currency and never
        converted; subscriptions billed in different currencies get charts
        of their own. When Cost Management reports no cost at all for a
        period, the view says so instead of drawing empty charts.

        Subscriptions Cost Management can't report on (some offer types,
        such as sponsorships, or missing permission) are listed with the
        reason under the charts rather than failing the run. Cost Management
        allows only a few queries a minute, so a progress display shows each
        subscription as it is read, and throttled requests are retried.

        Exports:
          -CsvPath    the detail: one row per subscription, month, resource
                      group and service - SubscriptionName, SubscriptionId,
                      Month, ResourceGroup, Service, Cost, Currency - ready
                      for an Excel pivot table
          -PdfPath    a landscape A4 report: a summary (totals, the
                      subscription-by-month table, top services and
                      resource groups this month), then a page per
                      subscription with its services and resource groups
                      month by month
          -PassThru   one AAC.SubscriptionCost object per subscription:
                      MonthToDate, one property per month ('2026-07', ...),
                      Total, TopServices and Status

        Reading costs needs Cost Management Reader (or Reader) on the
        subscriptions. Costs are "actual cost" as Cost Management reports
        it, which can lag usage by a day or so. PDF export needs Windows and
        PowerShell 7.4 or later.
    .PARAMETER SubscriptionId
        Only these subscriptions. Defaults to every enabled subscription the
        signed-in account can see.
    .PARAMETER Months
        How many months to cover, this month included (default 6, up to 12).
    .PARAMETER Top
        How many services the month-to-date breakdown shows (default 8); the
        rest are summed as "other services".
    .PARAMETER CsvPath
        Also write the detail - one row per subscription, month, resource
        group and service - to this CSV file. An existing file is
        overwritten; missing folders are created.
    .PARAMETER PdfPath
        Also write a PDF report to this file. An existing file is
        overwritten; missing folders are created.
    .PARAMETER Title
        The PDF's title. Defaults to 'Azure cost'.
    .PARAMETER PassThru
        Also return the costs as AAC.SubscriptionCost objects.
    .EXAMPLE
        Connect-AAC
        Show-AACCost
        Month to date and the last 6 months for every subscription you can see.
    .EXAMPLE
        Show-AACCost -Months 12 -CsvPath .\out\Cost.csv -PdfPath .\out\Cost.pdf
        The last year, on screen, as a detail CSV file and as a PDF report.
    .EXAMPLE
        Show-AACCost -SubscriptionId '00000000-0000-0000-0000-000000000000' -Months 3
        One subscription over the last three months.
    .EXAMPLE
        Show-AACCost -PassThru | Export-Csv .\CostSummary.csv -NoTypeInformation
        One row per subscription, with a column per month.
    .OUTPUTS
        AAC.SubscriptionCost (with -PassThru)
    #>
    [CmdletBinding()]
    [OutputType('AAC.SubscriptionCost')]
    param(
        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [ValidateRange(1, 12)]
        [int] $Months = 6,

        [ValidateRange(1, 20)]
        [int] $Top = 8,

        [string] $CsvPath,

        [string] $PdfPath,

        [string] $Title = 'Azure cost',

        [switch] $PassThru
    )

    # Resolve paths now, relative to the caller's location, so a bad path
    # fails before any Azure call.
    $csvFullPath = if ($CsvPath) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($CsvPath) }
    $pdfFullPath = if ($PdfPath) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($PdfPath) }

    # --- The period and helpers ------------------------------------------------------------------
    $invariant = [cultureinfo]::InvariantCulture
    $today = (Get-Date).Date
    $thisMonth = [datetime]::new($today.Year, $today.Month, 1)
    $monthStarts = @(for ($i = $Months - 1; $i -ge 0; $i--) { $thisMonth.AddMonths(-$i) })
    $monthKey = { param([datetime] $Date) $Date.ToString('yyyy-MM', $invariant) }
    $thisMonthKey = & $monthKey $thisMonth
    $lastMonthKey = & $monthKey $thisMonth.AddMonths(-1)

    # Cost Management's month column, whatever shape it arrives in: a
    # [datetime] (Invoke-RestMethod converts ISO dates), an ISO string, or a
    # number like 20260701. Always read in the invariant culture - a date
    # turned into text in the local culture ('01/07/2026') matches nothing.
    $toMonthKey = {
        param($Value)
        if ($null -eq $Value) { return }
        if ($Value -is [datetime]) { return $Value.ToString('yyyy-MM', $invariant) }
        if ($Value -is [datetimeoffset]) { return $Value.UtcDateTime.ToString('yyyy-MM', $invariant) }
        $text = ([string]$Value).Trim()
        if ($text -match '^(\d{4})(\d{2})\d{2}$') { return "$($Matches[1])-$($Matches[2])" }
        if ($text -match '^(\d{4})-(\d{2})') { return "$($Matches[1])-$($Matches[2])" }
        $parsed = [datetime]::MinValue
        if ([datetime]::TryParse($text, $invariant, [System.Globalization.DateTimeStyles]::None, [ref]$parsed)) { return $parsed.ToString('yyyy-MM', $invariant) }
    }
    # The sum of one property over some objects; 0 for none (Measure-Object
    # returns nothing at all for an empty list).
    $sum = {
        param($Items, [string] $Property)
        $total = 0.0
        foreach ($item in @($Items)) {
            $value = Get-AACPropertyValue -InputObject $item -Name $Property
            if ($null -ne $value) { $total += [double]$value }
        }
        $total
    }

    # One query per subscription: every month of the period, by service and
    # resource group. Month to date is simply this month's share of it.
    $query = @{
        type       = 'ActualCost'
        timeframe  = 'Custom'
        timePeriod = @{ from = $monthStarts[0].ToString('yyyy-MM-ddT00:00:00Z', $invariant); to = $today.ToString('yyyy-MM-ddT23:59:59Z', $invariant) }
        dataset    = @{
            granularity = 'Monthly'
            aggregation = @{ totalCost = @{ name = 'Cost'; function = 'Sum' } }
            grouping    = @(
                @{ type = 'Dimension'; name = 'ServiceName' }
                @{ type = 'Dimension'; name = 'ResourceGroupName' }
            )
        }
    }

    # --- Read and export behind one progress display, as Invoke-AACPester does ----------------
    # The title first; then a line per step - subscriptions, costs (naming
    # each subscription as it is read), CSV and PDF - each finishing with
    # what it found; then the report.
    Write-AACRule -Title 'Azure Admin Console :: Azure cost' -Color 'deepskyblue3_1'
    $headers = @{ Authorization = "Bearer $(Get-AACAccessToken)" }
    $state = Invoke-AACProgress -ScriptBlock {
        Update-AACProgress -Id 'subscriptions' -Description 'Finding subscriptions in Azure Resource Graph' -Indeterminate
        $subscriptions = @(Invoke-AACResourceGraphQuery -Headers $headers -Query "resourcecontainers | where type =~ 'microsoft.resources/subscriptions' | project subscriptionId, name, state = tostring(properties.state)")
        if ($SubscriptionId) {
            $wanted = @($SubscriptionId | ForEach-Object { $_.ToLowerInvariant() })
            $subscriptions = @($subscriptions | Where-Object { $_.subscriptionId.ToLowerInvariant() -in $wanted })
            foreach ($id in $wanted | Where-Object { $_ -notin @($subscriptions | ForEach-Object { $_.subscriptionId.ToLowerInvariant() }) }) {
                $subscriptions += [pscustomobject]@{ subscriptionId = $id; name = $id; state = 'Enabled' }
            }
        }
        else {
            $subscriptions = @($subscriptions | Where-Object { -not $_.state -or $_.state -eq 'Enabled' })
        }
        $subscriptions = @($subscriptions | Sort-Object name)
        Update-AACProgress -Id 'subscriptions' -Complete -Description ('Found {0} subscription(s)' -f $subscriptions.Count)

        # Cost Management allows only a few queries a minute: one per
        # subscription, each named as it is read.
        Update-AACProgress -Id 'cost' -Total $subscriptions.Count -Description "Reading costs for $($subscriptions.Count) subscription(s)"
        $index = 0
        $results = @(foreach ($subscription in $subscriptions) {
                $index++
                $name = if ($subscription.name) { $subscription.name } else { $subscription.subscriptionId }
                Update-AACProgress -Id 'cost' -Description "Reading costs: $name ($index of $($subscriptions.Count))"
                $rows = @()
                $status = 'OK'
                try {
                    $rows = @(Invoke-AACCostQuery -SubscriptionId $subscription.subscriptionId -Body $query)
                }
                catch {
                    $status = [string]$_.Exception.Message
                }
                Update-AACProgress -Id 'cost' -Increment 1
                @{ Subscription = $subscription; Name = $name; Rows = $rows; Status = $status }
            })
        $unreadable = @($results | Where-Object { $_.Status -ne 'OK' }).Count
        Update-AACProgress -Id 'cost' -Complete -Description ('Cost Management: {0} subscription(s) - {1} read{2}' -f $results.Count, ($results.Count - $unreadable), $(if ($unreadable) { ", $unreadable could not be read" }))

        # --- The detail: one row per subscription, month, resource group and service -------------
        $detail = [System.Collections.Generic.List[object]]::new()
        $costs = @(foreach ($result in $results) {
                $status = $result.Status
                $rows = @(foreach ($row in $result.Rows) {
                        $month = Get-AACPropertyValue -InputObject $row -Name 'BillingMonth'
                        if ($null -eq $month) { $month = Get-AACPropertyValue -InputObject $row -Name 'UsageDate' }
                        [pscustomobject]@{
                            PSTypeName       = 'AAC.CostDetail'
                            SubscriptionName = $result.Name
                            SubscriptionId   = $result.Subscription.subscriptionId
                            Month            = & $toMonthKey $month
                            ResourceGroup    = [string](Get-AACPropertyValue -InputObject $row -Name 'ResourceGroupName')
                            Service          = [string](Get-AACPropertyValue -InputObject $row -Name 'ServiceName')
                            Cost             = [Math]::Round([double](Get-AACPropertyValue -InputObject $row -Name 'Cost'), 4)
                            Currency         = [string](Get-AACPropertyValue -InputObject $row -Name 'Currency')
                        }
                    })
                # Never show a silent zero: rows whose month can't be read are an error.
                $unplaced = @($rows | Where-Object { -not $_.Month })
                if ($unplaced.Count -gt 0 -and $status -eq 'OK') {
                    $status = "$($unplaced.Count) of $($rows.Count) cost row(s) had a month that couldn't be read"
                }
                $rows = @($rows | Where-Object { $_.Month })
                foreach ($row in $rows) { $detail.Add($row) }

                $currency = @($rows | ForEach-Object { $_.Currency } | Where-Object { $_ } | Select-Object -First 1)
                $object = [ordered]@{
                    PSTypeName       = 'AAC.SubscriptionCost'
                    SubscriptionName = $result.Name
                    SubscriptionId   = $result.Subscription.subscriptionId
                    Currency         = if ($currency) { [string]$currency[0] } else { '' }
                    MonthToDate      = [Math]::Round((& $sum @($rows | Where-Object Month -eq $thisMonthKey) 'Cost'), 2)
                }
                foreach ($start in $monthStarts) {
                    $key = & $monthKey $start
                    $object[$key] = [Math]::Round((& $sum @($rows | Where-Object Month -eq $key) 'Cost'), 2)
                }
                $object['Total'] = [Math]::Round((& $sum $rows 'Cost'), 2)
                $services = @($rows | Where-Object Month -eq $thisMonthKey | Group-Object Service | ForEach-Object {
                        [pscustomobject]@{ Name = $_.Name; Cost = (& $sum $_.Group 'Cost') }
                    } | Sort-Object Cost -Descending)
                $object['TopServices'] = (@($services | Select-Object -First 3 | ForEach-Object { '{0} ({1:N2})' -f $_.Name, $_.Cost })) -join '; '
                $object['Status'] = $status
                [pscustomobject]$object
            })

        $period = "$($monthStarts[0].ToString('MMM yyyy')) - $($today.ToString('d MMM yyyy'))"
        $pdf = Invoke-AACExport -CsvPath $csvFullPath -CsvObject @($detail | Sort-Object SubscriptionName, Month, ResourceGroup, Service) -Noun 'detail row' -PdfPath $pdfFullPath -WritePdf {
            Write-AACCostPdf -Cost $costs -Detail $detail.ToArray() -MonthStart $monthStarts -Path $pdfFullPath -Title $Title -Period $period
        }

        @{ Subscriptions = $subscriptions; Costs = $costs; Detail = $detail; Pdf = $pdf }
    }
    $subscriptions = @($state.Subscriptions)
    $costs = @($state.Costs)
    $detail = $state.Detail
    $pdf = $state.Pdf

    # --- The view --------------------------------------------------------------------------------
    $escape = { param($Text) [Spectre.Console.Markup]::Escape([string]$Text) }
    # Unicode symbols, or ASCII in a console that isn't UTF-8.
    $glyph = Get-AACGlyph
    $money = { param([double] $Value, [string] $Currency) ('{0:N2} {1}' -f $Value, $Currency).Trim() }
    $monthLabel = { param([datetime] $Start) "$($Start.ToString('MMM yyyy'))$(if ($Start -eq $thisMonth) { ' (to date)' })" }
    $facts = [System.Collections.Generic.List[string]]::new()
    if ($global:AACSession) {
        $facts.Add("[white]$(& $escape $global:AACSession.Account)[/]")
        $facts.Add("tenant $(& $escape $global:AACSession.TenantId)")
    }
    $facts.Add("$($subscriptions.Count) subscription(s)")
    $facts.Add("actual cost $($monthStarts[0].ToString('MMM yyyy')) - $($today.ToString('d MMM yyyy'))")
    Write-AACMarkup "[grey58]$($facts -join " $($glyph.Dot) ")[/]"
    [Spectre.Console.AnsiConsole]::WriteLine()

    $read = @($costs | Where-Object Status -eq 'OK')
    if ($read.Count -eq 0) {
        Show-AACPanel -Content '[bold]No costs could be read[/] [grey58]for these subscriptions - see the reasons below.[/]' -BorderColor 'grey50' -AllowMarkup
    }
    $currencyGroups = @($read | Group-Object -Property Currency | Sort-Object -Property Count -Descending)
    foreach ($currencyGroup in $currencyGroups) {
        $currency = $currencyGroup.Name
        $group = @($currencyGroup.Group)
        $ids = @($group | ForEach-Object { $_.SubscriptionId })
        $rows = @($detail | Where-Object { $_.SubscriptionId -in $ids })
        if ($currencyGroups.Count -gt 1) {
            Write-AACRule -Title "[bold]$(& $escape $(if ($currency) { $currency } else { 'no currency' }))[/]" -Color 'grey50'
        }

        $monthToDate = & $sum $group 'MonthToDate'
        $periodTotal = & $sum $group 'Total'
        $thisMonthRows = @($rows | Where-Object Month -eq $thisMonthKey)
        $byService = @($thisMonthRows | Group-Object Service | ForEach-Object { [pscustomobject]@{ Name = $(if ($_.Name) { $_.Name } else { '(no service)' }); Cost = (& $sum $_.Group 'Cost') } } | Where-Object Cost -gt 0 | Sort-Object Cost -Descending)
        $byGroup = @($thisMonthRows | Group-Object ResourceGroup | ForEach-Object { [pscustomobject]@{ Name = $(if ($_.Name) { $_.Name } else { '(no resource group)' }); Cost = (& $sum $_.Group 'Cost') } } | Where-Object Cost -gt 0 | Sort-Object Cost -Descending)

        Show-AACTileRow -Tile @(
            @{ Value = (& $money $monthToDate $currency); Caption = 'month to date'; Color = 'springgreen2' }
            @{ Value = $(if ($Months -gt 1) { & $money (& $sum $group $lastMonthKey) $currency } else { '-' }); Caption = 'last month'; Color = 'deepskyblue1' }
            @{ Value = (& $money $periodTotal $currency); Caption = "last $Months month$(if ($Months -ne 1) { 's' })"; Color = 'mediumpurple2' }
            @{ Value = '{0:N0}' -f $group.Count; Caption = 'subscriptions'; Color = 'gold1' }
            @{ Value = $(if ($byService) { $byService[0].Name } else { '-' }); Caption = 'top service this month'; Color = 'hotpink' }
        )
        [Spectre.Console.AnsiConsole]::WriteLine()

        if ($periodTotal -eq 0) {
            Show-AACPanel -Content "[bold]Cost Management reports no cost[/] [grey58]for $(if ($group.Count -eq 1) { 'this subscription' } else { 'these subscriptions' }) from $($monthStarts[0].ToString('MMM yyyy')) to today. Its usage may be billed to another subscription, be covered by credits, or not be processed yet.[/]" -BorderColor 'grey50' -AllowMarkup
            [Spectre.Console.AnsiConsole]::WriteLine()
            continue
        }

        if ($group.Count -gt 1) {
            $bars = @($group | Sort-Object -Property MonthToDate -Descending | ForEach-Object { @{ Label = $_.SubscriptionName; Value = $_.MonthToDate } })
            Show-AACBarChart -Item $bars -Title "Month to date by subscription ($currency)" -Format 'N2'
            [Spectre.Console.AnsiConsole]::WriteLine()
        }
        if ($byService) {
            $slices = [ordered]@{}
            foreach ($service in @($byService | Select-Object -First $Top)) { $slices[[string]$service.Name] = [Math]::Round($service.Cost, 2) }
            $other = @($byService | Select-Object -Skip $Top)
            if ($other) { $slices['other services'] = [Math]::Round((& $sum $other 'Cost'), 2) }
            Show-AACBreakdownChart -Data $slices -Title "Month to date by service ($currency)" -Width 120
            [Spectre.Console.AnsiConsole]::WriteLine()
        }
        if ($byGroup) {
            $bars = @($byGroup | Select-Object -First 10 | ForEach-Object { @{ Label = $_.Name; Value = [Math]::Round($_.Cost, 2) } })
            Show-AACBarChart -Item $bars -Title "Month to date by resource group ($currency, top $([Math]::Min(10, $byGroup.Count)) of $($byGroup.Count))" -Format 'N2'
            [Spectre.Console.AnsiConsole]::WriteLine()
        }
        if ($Months -gt 1) {
            $monthBars = @(foreach ($start in $monthStarts) {
                    @{ Label = (& $monthLabel $start); Value = (& $sum $group (& $monthKey $start)); Color = $(if ($start -eq $thisMonth) { 'springgreen2' } else { 'deepskyblue1' }) }
                })
            Show-AACBarChart -Item $monthBars -Title "Last $Months months ($currency)" -Format 'N2'
            [Spectre.Console.AnsiConsole]::WriteLine()
        }

        # Every subscription month by month, with a total column (and row).
        $table = [Spectre.Console.Table]::new()
        $table.Border = [Spectre.Console.TableBorder]::Rounded
        $table.BorderStyle = [Spectre.Console.Style]::Parse('grey35')
        $table.Title = [Spectre.Console.TableTitle]::new("[bold]Actual cost by subscription and month ($(& $escape $currency))[/]")
        $table.AddColumn([Spectre.Console.TableColumn]::new('[grey62]Subscription[/]')) | Out-Null
        foreach ($header in @($monthStarts | ForEach-Object { "$($_.ToString('MMM yy'))$(if ($_ -eq $thisMonth) { '*' })" }) + 'Total') {
            $column = [Spectre.Console.TableColumn]::new("[grey62]$header[/]")
            $column.Alignment = [Spectre.Console.Justify]::Right
            $table.AddColumn($column) | Out-Null
        }
        $cell = { param([double] $Value, [string] $Style) $text = '{0:N2}' -f $Value; [Spectre.Console.Markup]::new($(if ($Value -eq 0) { "[grey42]$text[/]" } elseif ($Style) { "[$Style]$text[/]" } else { $text })) }
        foreach ($item in @($group | Sort-Object -Property Total -Descending)) {
            $values = @($monthStarts | ForEach-Object { [double]$item.(& $monthKey $_) })
            $peak = ($values | Measure-Object -Maximum).Maximum
            $cells = @([Spectre.Console.Markup]::new("[bold]$(& $escape $item.SubscriptionName)[/]"))
            foreach ($value in $values) { $cells += & $cell $value $(if ($value -eq $peak -and $value -gt 0) { 'bold gold1' }) }
            $cells += & $cell $item.Total 'bold'
            [Spectre.Console.TableExtensions]::AddRow($table, [Spectre.Console.Rendering.IRenderable[]]$cells) | Out-Null
        }
        if ($group.Count -gt 1) {
            $cells = @([Spectre.Console.Markup]::new('[bold]Total[/]'))
            foreach ($start in $monthStarts) { $cells += & $cell (& $sum $group (& $monthKey $start)) 'bold' }
            $cells += & $cell $periodTotal 'bold'
            $table.ShowFooters = $false
            [Spectre.Console.TableExtensions]::AddEmptyRow($table) | Out-Null
            [Spectre.Console.TableExtensions]::AddRow($table, [Spectre.Console.Rendering.IRenderable[]]$cells) | Out-Null
        }
        [Spectre.Console.AnsiConsole]::Write($table)
        Write-AACMarkup "[grey42]* month to date. Each subscription's highest month is in gold.[/]"
        [Spectre.Console.AnsiConsole]::WriteLine()
    }

    foreach ($failed in @($costs | Where-Object Status -ne 'OK')) {
        Write-AACMarkup "[orange1]![/] [grey58]$(& $escape $failed.SubscriptionName): $(& $escape $failed.Status)[/]"
    }
    if ($csvFullPath) { Write-AACMarkup "[grey58]CSV written to[/] [link]$(& $escape $csvFullPath)[/] [grey42]($($detail.Count) detail rows)[/]" }
    if ($pdf) { Write-AACMarkup "[grey58]PDF written to[/] [link]$(& $escape $pdf.FullName)[/]" }

    if ($PassThru) {
        $costs
    }
}
