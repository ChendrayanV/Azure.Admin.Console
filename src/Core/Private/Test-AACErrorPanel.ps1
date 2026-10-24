function Test-AACErrorPanel {
    <#
    .SYNOPSIS
        Whether Show-AACError draws its panel: only at an interactive
        console, and not when the caller silenced errors (-ErrorAction
        SilentlyContinue or Ignore).
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.PSCmdlet] $Cmdlet
    )

    # -ErrorAction on the command itself, else the session's preference (a
    # trap doesn't see the -ErrorAction value as a variable).
    $bound = $Cmdlet.MyInvocation.BoundParameters
    $preference = if ($bound.ContainsKey('ErrorAction')) { $bound['ErrorAction'] } else { $Cmdlet.GetVariableValue('ErrorActionPreference') }
    if ("$preference" -in 'SilentlyContinue', 'Ignore') {
        return $false
    }
    [bool][Spectre.Console.AnsiConsole]::Profile.Capabilities.Interactive
}
