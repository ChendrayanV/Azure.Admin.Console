function Get-AACSeverityRank {
    <#
    .SYNOPSIS
        The order, tone and status of each severity, for sorting and drawing
        findings the same way in every command.
    .DESCRIPTION
          Severity  Rank  Tone (HTML)  Status (console)
          Critical  0     bad          Failed
          High      1     bad          Failed
          Medium    2     warn         Warning
          Low       3     info         Info
          Info      4     neutral      Info
        Returns @{ Rank; Tone; Status } hashtables keyed by severity.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    @{
        Rank   = @{ Critical = 0; High = 1; Medium = 2; Low = 3; Info = 4 }
        Tone   = @{ Critical = 'bad'; High = 'bad'; Medium = 'warn'; Low = 'info'; Info = 'neutral' }
        Status = @{ Critical = 'Failed'; High = 'Failed'; Medium = 'Warning'; Low = 'Info'; Info = 'Info' }
    }
}
