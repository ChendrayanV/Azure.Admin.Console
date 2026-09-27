function Write-AACExceptionHtml {
    <#
    .SYNOPSIS
        Writes Invoke-AACApplicationInsightQuery's -HtmlPath report for
        exceptions: tiles, charts by type, severity, operation and app, and
        every exception in one interactive table, grouped by type.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Exception,

        [Parameter(Mandatory)]
        [string] $Path,

        [string] $Title = 'Application Insights exceptions',

        [System.Collections.IDictionary] $Detail
    )

    $count = { param($Items) $n = 0; foreach ($item in @($Items)) { $n += [int]$item.ItemCount }; $n }
    $distinct = { param([string] $Property) @($Exception | ForEach-Object { $_.$Property } | Where-Object { $_ } | Select-Object -Unique).Count }
    $severityTone = @{ Critical = 'bad'; Error = 'bad'; Warning = 'warn'; Information = 'info'; Verbose = 'neutral' }
    $top = {
        param([string] $Property, [int] $First = 10)
        @($Exception | Group-Object -Property $Property | ForEach-Object {
                @{ Label = $(if ($_.Name) { $_.Name } else { '(none)' }); Value = (& $count $_.Group) }
            } | Sort-Object -Property { $_.Value } -Descending | Select-Object -First $First)
    }
    $serious = & $count @($Exception | Where-Object { $_.Severity -in 'Error', 'Critical' })
    $tiles = @(
        @{ Value = '{0:N0}' -f (& $count $Exception); Label = 'exceptions'; Tone = 'bad'; Table = 'exceptions' }
        @{ Value = '{0:N0}' -f (& $distinct 'ProblemId'); Label = 'problems'; Tone = 'warn' }
        @{ Value = '{0:N0}' -f (& $distinct 'ExceptionType'); Label = 'exception types'; Tone = 'violet' }
        @{ Value = '{0:N0}' -f (& $distinct 'OperationName'); Label = 'operations'; Tone = 'info' }
        @{ Value = '{0:N0}' -f (& $distinct 'AppRoleName'); Label = 'apps / roles'; Tone = 'good' }
        @{ Value = '{0:N0}' -f $serious; Label = 'errors and critical'; Tone = $(if ($serious) { 'bad' } else { 'neutral' }); Table = 'exceptions'; Filters = @{ Severity = 'Error' } }
    )
    $bySeverity = @(foreach ($name in 'Critical', 'Error', 'Warning', 'Information', 'Verbose') {
            $n = & $count @($Exception | Where-Object Severity -EQ $name)
            if ($n) { @{ Label = $name; Value = $n; Tone = $severityTone[$name] } }
        })
    $charts = @(
        @{ Title = 'Top exception types'; Items = @(& $top 'ExceptionType'); Table = 'exceptions'; Column = 'ExceptionType'; Tone = 'bad'; Wide = $true }
        @{ Title = 'By severity'; Items = $bySeverity; Table = 'exceptions'; Column = 'Severity' }
        @{ Title = 'By operation'; Items = @(& $top 'OperationName'); Table = 'exceptions'; Column = 'OperationName'; Tone = 'info' }
        @{ Title = 'By app / role'; Items = @(& $top 'AppRoleName'); Table = 'exceptions'; Column = 'AppRoleName'; Tone = 'good' }
    )
    $table = @{
        Id      = 'exceptions'
        Title   = 'Exceptions'
        Note    = 'Newest first. Group by problem, operation or app; the CSV download has every column.'
        Noun    = 'exceptions'
        File    = 'AppInsightsExceptions'
        Rows    = $Exception
        Sort    = @{ Key = 'TimeGenerated'; Desc = $true }
        Group   = 'ExceptionType'
        GroupBy = @('ExceptionType', 'ProblemId', 'OperationName', 'AppRoleName', 'Severity')
        Columns = @(
            @{ Key = 'TimeGenerated'; Label = 'Time'; Type = 'datetime' }
            @{ Key = 'Severity'; Label = 'Severity'; Type = 'badge'; Facet = $true; Tones = $severityTone }
            @{ Key = 'ExceptionType'; Label = 'Type'; Facet = $true; Type = 'mono' }
            @{ Key = 'Message'; Label = 'Message'; Type = 'wide' }
            @{ Key = 'StackTop'; Label = 'Thrown at'; Type = 'mono' }
            @{ Key = 'OperationName'; Label = 'Operation'; Facet = $true }
            @{ Key = 'AppRoleName'; Label = 'App / role'; Facet = $true; Nowrap = $true }
            @{ Key = 'AppRoleInstance'; Label = 'Instance'; Nowrap = $true }
            @{ Key = 'ClientCountryOrRegion'; Label = 'Country'; Facet = $true }
            @{ Key = 'ItemCount'; Label = 'Count'; Type = 'number'; Sum = $true }
            @{ Key = 'ProblemId'; Label = 'Problem'; Hidden = $true }
            @{ Key = 'OuterType'; Label = 'Outer type'; Hidden = $true }
            @{ Key = 'OuterMessage'; Label = 'Outer message'; Hidden = $true }
            @{ Key = 'InnermostType'; Label = 'Innermost type'; Hidden = $true }
            @{ Key = 'InnermostMessage'; Label = 'Innermost message'; Hidden = $true }
            @{ Key = 'DetailType'; Label = 'Detail type'; Hidden = $true }
            @{ Key = 'DetailMessage'; Label = 'Detail message'; Hidden = $true }
            @{ Key = 'DetailSeverityLevel'; Label = 'Detail severity level'; Hidden = $true }
            @{ Key = 'Method'; Label = 'Method'; Hidden = $true }
            @{ Key = 'Assembly'; Label = 'Assembly'; Hidden = $true }
            @{ Key = 'OperationId'; Label = 'Operation ID'; Hidden = $true }
            @{ Key = 'AppVersion'; Label = 'App version'; Hidden = $true }
            @{ Key = 'CustomProperties'; Label = 'Custom properties'; Hidden = $true }
        )
    }
    Write-AACHtmlReport -Path $Path -Title $Title -Subtitle "$('{0:N0}' -f (& $count $Exception)) exceptions" -Fact $Detail -Tile $tiles -Chart $charts -Table @($table)
}
