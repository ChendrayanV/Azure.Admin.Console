function Get-AACFreeLoopbackPort {
    <#
    .SYNOPSIS
        Asks the OS for a free TCP port on the loopback address.
    .DESCRIPTION
        Binds a TcpListener to port 0 (which tells the OS to pick any free port),
        reads back the port it was assigned, then immediately stops listening.
        There is an inherent, unavoidable race between that and the caller later
        binding its own listener to the same port, but it is the standard way to
        reserve a free loopback port for a one-shot OAuth redirect and the odds
        of collision in that short window are negligible.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param()

    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    try {
        $listener.Start()
        return $listener.LocalEndpoint.Port
    }
    finally {
        $listener.Stop()
    }
}
