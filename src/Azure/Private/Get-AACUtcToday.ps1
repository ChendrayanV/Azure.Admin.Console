function Get-AACUtcToday {
    <#
    .SYNOPSIS
        Today's date in UTC.
    .DESCRIPTION
        A function so that a test can pin the date: what Get-AACCostAnomaly
        finds depends on where its window ends in the month.
    #>
    [CmdletBinding()]
    [OutputType([datetime])]
    param()

    [datetime]::UtcNow.Date
}
