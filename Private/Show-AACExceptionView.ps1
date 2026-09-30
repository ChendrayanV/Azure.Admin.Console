function Show-AACExceptionView {
    <#
    .SYNOPSIS
        Renders Application Insights exceptions (AAC.ApplicationInsightsException)
        as a Spectre.Console view.
    .DESCRIPTION
        The source and time range, tiles (exceptions, problems, exception
        types, operations, apps, errors and critical), then:

          Exceptions over time     a bar per time slot (10 minutes up to 2
                                   hours, hourly up to 2 days, else daily)
          By severity              one bar split by severity level
          Top exception types      the most frequent types
          Top problems             one row per problem (type and method):
                                   count, last seen, apps, a sample message
          Latest exceptions        every exception, newest first, with severity badges

        Counts use each row's ItemCount, so sampled telemetry counts right.
        Output goes straight to the Spectre console; wrap the call in
        Invoke-AACPagedOutput to page it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Exception,

        [System.Collections.IDictionary] $Scope,

        [timespan] $Range = [timespan]::FromHours(2),

        # How many of the newest exceptions to list; 0 (the default) lists
        # them all - Invoke-AACPagedOutput pages them.
        [ValidateRange(0, [int]::MaxValue)]
        [int] $Latest = 0
    )

    $escape = { param($Text) [Spectre.Console.Markup]::Escape([string]$Text) }
    $clip = { param([string] $Text, [int] $Length) if ($Text.Length -gt $Length) { $Text.Substring(0, $Length - 3) + '...' } else { $Text } }
    $glyph = Get-AACGlyph
    $count = { param($Items) $n = 0; foreach ($item in @($Items)) { $n += [int]$item.ItemCount }; $n }
    $severityColor = [ordered]@{ Critical = 'red3'; Error = 'indianred1'; Warning = 'orange1'; Information = 'deepskyblue1'; Verbose = 'grey50' }
    $badge = @{
        Critical    = '[bold white on red3] CRITICAL [/]'
        Error       = '[bold white on indianred1] ERROR [/]'
        Warning     = '[bold black on orange1] WARNING [/]'
        Information = '[black on deepskyblue1] INFO [/]'
        Verbose     = '[black on grey70] VERBOSE [/]'
    }

    $facts = [System.Collections.Generic.List[string]]::new()
    if ($script:AACSession) { $facts.Add("[white]$(& $escape $script:AACSession.Account)[/]") }
    if ($Scope) { foreach ($key in $Scope.Keys) { $facts.Add("$(& $escape $key): $(& $escape $Scope[$key])") } }
    Write-AACMarkup "[grey58]$($facts -join " $($glyph.Dot) ")[/]"
    [Spectre.Console.AnsiConsole]::WriteLine()

    if ($Exception.Count -eq 0) {
        Show-AACPanel -Content '[bold green3]No exceptions[/] [grey58]in this time range and with these filters.[/]' -BorderColor 'green3' -AllowMarkup
        return
    }

    $total = & $count $Exception
    $serious = & $count @($Exception | Where-Object { $_.Severity -in 'Error', 'Critical' })
    $distinct = { param([string] $Property) @($Exception | ForEach-Object { $_.$Property } | Where-Object { $_ } | Select-Object -Unique).Count }
    Show-AACTileRow -Tile @(
        @{ Value = '{0:N0}' -f $total; Caption = 'exceptions'; Color = 'indianred1' }
        @{ Value = '{0:N0}' -f (& $distinct 'ProblemId'); Caption = 'problems'; Color = 'orange1' }
        @{ Value = '{0:N0}' -f (& $distinct 'ExceptionType'); Caption = 'exception types'; Color = 'mediumpurple2' }
        @{ Value = '{0:N0}' -f (& $distinct 'OperationName'); Caption = 'operations'; Color = 'deepskyblue1' }
        @{ Value = '{0:N0}' -f (& $distinct 'AppRoleName'); Caption = 'apps / roles'; Color = 'green3' }
        @{ Value = '{0:N0}' -f $serious; Caption = 'errors and critical'; Color = $(if ($serious) { 'red3' } else { 'grey50' }) }
    )
    [Spectre.Console.AnsiConsole]::WriteLine()

    # Over time: a bar per slot, in local time.
    $slot = if ($Range.TotalHours -le 2) { [timespan]::FromMinutes(10) } elseif ($Range.TotalHours -le 48) { [timespan]::FromHours(1) } else { [timespan]::FromDays(1) }
    $format = if ($slot.TotalDays -ge 1) { 'ddd d MMM' } elseif ($Range.TotalHours -le 24) { 'HH:mm' } else { 'ddd HH:mm' }
    $end = [datetime]::UtcNow
    $bucketCount = [Math]::Min(48, [int][Math]::Ceiling($Range.Ticks / $slot.Ticks))
    $first = [datetime]::new($end.Ticks - ($end.Ticks % $slot.Ticks) - ($bucketCount - 1) * $slot.Ticks, [DateTimeKind]::Utc)
    $buckets = [ordered]@{}
    for ($i = 0; $i -lt $bucketCount; $i++) { $buckets[$first.AddTicks($i * $slot.Ticks)] = 0 }
    foreach ($item in $Exception) {
        if (-not $item.TimeGenerated -or $item.TimeGenerated -lt $first) { continue }
        $key = [datetime]::new($item.TimeGenerated.Ticks - ($item.TimeGenerated.Ticks % $slot.Ticks), [DateTimeKind]::Utc)
        if ($buckets.Contains($key)) { $buckets[$key] += [int]$item.ItemCount }
    }
    $peak = ($buckets.Values | Measure-Object -Maximum).Maximum
    $bars = @(foreach ($key in $buckets.Keys) {
            @{ Label = $key.ToLocalTime().ToString($format); Value = $buckets[$key]; Color = $(if ($buckets[$key] -eq $peak -and $peak -gt 0) { 'red3' } else { 'indianred1' }) }
        })
    Show-AACBarChart -Item $bars -Title "Exceptions over time (per $(if ($slot.TotalDays -ge 1) { 'day' } elseif ($slot.TotalHours -ge 1) { 'hour' } else { '10 minutes' }), local time)"
    [Spectre.Console.AnsiConsole]::WriteLine()

    $bySeverity = [ordered]@{}
    $colors = @{}
    foreach ($name in $severityColor.Keys) {
        $n = & $count @($Exception | Where-Object Severity -EQ $name)
        if ($n) { $bySeverity[$name] = $n; $colors[$name] = $severityColor[$name] }
    }
    if ($bySeverity.Count) {
        Show-AACBreakdownChart -Data $bySeverity -Title 'By severity' -Color $colors -Width 100
        [Spectre.Console.AnsiConsole]::WriteLine()
    }

    $types = @($Exception | Group-Object -Property ExceptionType | ForEach-Object { @{ Label = $(if ($_.Name) { & $clip $_.Name 60 } else { '(no type)' }); Value = (& $count $_.Group) } } | Sort-Object -Property { $_.Value } -Descending | Select-Object -First 8)
    Show-AACBarChart -Item $types -Title 'Top exception types'
    [Spectre.Console.AnsiConsole]::WriteLine()

    # Top problems: a problem is a type thrown from one place.
    $problems = @($Exception | Group-Object -Property { if ($_.ProblemId) { $_.ProblemId } else { "$($_.ExceptionType) at $($_.Method)" } } |
            ForEach-Object {
                $items = @($_.Group | Sort-Object -Property TimeGenerated -Descending)
                [pscustomobject]@{ Problem = $_.Name; Count = (& $count $items); Last = $items[0].TimeGenerated; Sample = $items[0]; Apps = (@($items.AppRoleName | Where-Object { $_ } | Select-Object -Unique) -join ', ') }
            } | Sort-Object -Property Count -Descending | Select-Object -First 10)
    $table = [Spectre.Console.Table]::new()
    $table.Border = [Spectre.Console.TableBorder]::Rounded
    $table.BorderStyle = [Spectre.Console.Style]::Parse('indianred1')
    $table.Expand = $true
    $table.Title = [Spectre.Console.TableTitle]::new("[bold indianred1]$($glyph.Bullet) Top problems[/] [grey58]$($glyph.Dot) by count[/]")
    foreach ($header in @(@('Count', 7), @('Problem', 0), @('Last seen', 10), @('Apps / roles', 18), @('Sample message', 0))) {
        $column = [Spectre.Console.TableColumn]::new("[grey62]$($header[0])[/]")
        if ($header[1]) { $column.Width = $header[1] }
        if ($header[0] -eq 'Count') { $column.Alignment = [Spectre.Console.Justify]::Right }
        $table.AddColumn($column) | Out-Null
    }
    foreach ($problem in $problems) {
        $sample = $problem.Sample
        $cells = @(
            [Spectre.Console.Markup]::new("[bold indianred1]$('{0:N0}' -f $problem.Count)[/]")
            [Spectre.Console.Markup]::new("[white]$(& $escape (& $clip $sample.ExceptionType 200))[/]$(if ($sample.Method) { "`n[grey50]at $(& $escape (& $clip $sample.Method 200))[/]" })")
            [Spectre.Console.Markup]::new("[grey70]$(if ($problem.Last) { $problem.Last.ToLocalTime().ToString('HH:mm:ss') })[/]")
            [Spectre.Console.Markup]::new("[deepskyblue1]$(& $escape (& $clip $problem.Apps 200))[/]")
            [Spectre.Console.Markup]::new("[grey70]$(& $escape (& $clip $sample.Message 600))[/]")
        )
        [Spectre.Console.TableExtensions]::AddRow($table, [Spectre.Console.Rendering.IRenderable[]]$cells) | Out-Null
    }
    [Spectre.Console.AnsiConsole]::Write($table)
    [Spectre.Console.AnsiConsole]::WriteLine()

    # The latest exceptions.
    $recent = @($Exception | Sort-Object -Property TimeGenerated -Descending)
    if ($Latest -gt 0) { $recent = @($recent | Select-Object -First $Latest) }
    $table = [Spectre.Console.Table]::new()
    $table.Border = [Spectre.Console.TableBorder]::Rounded
    $table.BorderStyle = [Spectre.Console.Style]::Parse('grey42')
    $table.Expand = $true
    $table.Title = [Spectre.Console.TableTitle]::new("[bold]$($glyph.Bullet) Latest exceptions[/] [grey58]$($glyph.Dot) $($recent.Count) of $('{0:N0}' -f $Exception.Count)[/]")
    foreach ($header in @(@('Time', 10), @('Severity', 12), @('Exception', 0), @('Operation', 0), @('App / role', 18))) {
        $column = [Spectre.Console.TableColumn]::new("[grey62]$($header[0])[/]")
        if ($header[1]) { $column.Width = $header[1] }
        $table.AddColumn($column) | Out-Null
    }
    foreach ($item in $recent) {
        $severity = if ($badge.ContainsKey([string]$item.Severity)) { $badge[[string]$item.Severity] } else { "[grey70]$(& $escape $item.Severity)[/]" }
        $what = "[white]$(& $escape (& $clip $item.ExceptionType 200))[/]"
        if ($item.Message) { $what += "`n[grey58]$(& $escape (& $clip $item.Message 600))[/]" }
        if ($item.StackTop) { $what += "`n[grey42]at $(& $escape (& $clip $item.StackTop 300))[/]" }
        $cells = @(
            [Spectre.Console.Markup]::new("[grey70]$(if ($item.TimeGenerated) { $item.TimeGenerated.ToLocalTime().ToString('HH:mm:ss') })[/]")
            [Spectre.Console.Markup]::new($severity)
            [Spectre.Console.Markup]::new($what)
            [Spectre.Console.Markup]::new("[deepskyblue1]$(& $escape (& $clip $item.OperationName 200))[/]")
            [Spectre.Console.Markup]::new("[green3]$(& $escape $item.AppRoleName)[/]$(if ($item.AppRoleInstance) { "`n[grey50]$(& $escape (& $clip $item.AppRoleInstance 100))[/]" })")
        )
        [Spectre.Console.TableExtensions]::AddRow($table, [Spectre.Console.Rendering.IRenderable[]]$cells) | Out-Null
    }
    [Spectre.Console.AnsiConsole]::Write($table)
}
