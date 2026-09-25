function Disconnect-AAC {
    <#
    .SYNOPSIS
        Clears the current Azure sign-in from memory.
    .DESCRIPTION
        Discards the cached access token, refresh token and account/tenant info
        that Connect-AAC stored. Nothing was ever written to disk, so this simply
        forgets the in-memory session; commands that need Azure access (like
        Invoke-AACPester) will require Connect-AAC again afterwards.
    .EXAMPLE
        Disconnect-AAC
    #>
    [CmdletBinding()]
    param()

    if (-not $global:AACSession) {
        Write-AACMarkup '[grey58]Not connected - nothing to do.[/]'
        return
    }

    $account = $global:AACSession.Account
    $global:AACSession = $null
    Write-AACMarkup "[green1]Disconnected $account.[/]"
}
