function Open-AACFile {
    <#
    .SYNOPSIS
        Opens a file with the system's default app - an HTML report in the
        default browser. A function of its own so tests can replace it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    # PowerShell 7 hands the file to the shell on every platform (the
    # default browser on Windows, 'open' on macOS, xdg-open on Linux).
    Start-Process -FilePath $Path | Out-Null
}
