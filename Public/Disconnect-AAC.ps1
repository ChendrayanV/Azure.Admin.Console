function Disconnect-AAC {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Clears the current Azure sign-in from memory.
    .DESCRIPTION
        Discards the cached access token, refresh token and account/tenant info
        that Connect-AAC stored. Nothing was ever written to disk, so this simply
        forgets the in-memory session; commands that need Azure access (like
        Invoke-AACPSRule) will require Connect-AAC again afterwards.
    .EXAMPLE
        Disconnect-AAC
    #>
    [CmdletBinding()]
    param()

    # A failure anywhere below ends as a Spectre.Console error panel and this
    # command's own terminating error, not a line inside the module.
    trap { $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    if (-not $script:AACSession) {
        Write-AACMarkup '[grey58]Not connected - nothing to do.[/]'
        return
    }

    $account = $script:AACSession.Account
    $script:AACSession = $null
    Write-AACMarkup "[green1]Disconnected $account.[/]"
}
