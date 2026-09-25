function Invoke-AACStatus {
    <#
    .SYNOPSIS
        Runs a script block behind a Spectre.Console spinner, returning whatever
        the script block returns.
    .DESCRIPTION
        Wraps [Spectre.Console.AnsiConsole]::Status().Start(title, Action<StatusContext>).
        Start() is synchronous and returns void, so the script block's result is
        captured into a [ref] cell from inside the delegate and read back out
        once Start() returns - a plain closure over a local variable is not used
        here because it is the [ref] cell's identity, not PowerShell variable
        scoping, that reliably survives the scriptblock-to-Action<T> conversion.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Title,

        [Parameter(Mandatory)]
        [scriptblock] $ScriptBlock,

        [ValidateSet('Dots', 'Dots2', 'Dots3', 'Line', 'Star', 'Star2', 'Arrow3', 'BouncingBar', 'Clock')]
        [string] $Spinner = 'Dots'
    )

    $resultHolder = [ref]$null
    $action = [Action[Spectre.Console.StatusContext]] {
        param($context)
        $resultHolder.Value = & $ScriptBlock $context
    }

    $status = [Spectre.Console.AnsiConsole]::Status()
    $status.Spinner = [Spectre.Console.Spinner+Known]::$Spinner
    $status.Start($Title, $action)

    return $resultHolder.Value
}
