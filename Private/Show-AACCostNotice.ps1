function Show-AACCostNotice {
    <#
    .SYNOPSIS
        Writes a line for each subscription Show-AACCost has nothing to chart
        for: grey for one with no cost in the period, orange with the reason
        for one that couldn't be read.
    .DESCRIPTION
          · sub-sandbox: no cost since Apr 2026
          ! sub-dev: Cost Management data is not available for subscription offer type ...
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Cost,

        [Parameter(Mandatory)]
        [datetime] $Since
    )

    $escape = { param($Text) [Spectre.Console.Markup]::Escape([string]$Text) }
    $glyph = Get-AACGlyph
    foreach ($item in @($Cost | Where-Object Status -EQ 'No cost')) {
        Write-AACMarkup "[grey58]$($glyph.Dot) $(& $escape $item.SubscriptionName): no cost since $($Since.ToString('MMM yyyy'))[/]"
    }
    foreach ($item in @($Cost | Where-Object { $_.Status -notin 'OK', 'No cost' })) {
        Write-AACMarkup "[orange1]![/] [grey58]$(& $escape $item.SubscriptionName): $(& $escape $item.Status)[/]"
    }
}
