function Invoke-AACArmRequest {
    <#
    .SYNOPSIS
        Calls Azure Resource Manager with the Connect-AAC sign-in and returns
        the JSON response as hashtables.
    .DESCRIPTION
        Invoke-RestMethod can't be used for resource data: it silently returns
        the raw text when the JSON has keys differing only by case - which
        tags often do ('Owner' and 'owner' on one resource) - while
        ConvertFrom-Json -AsHashtable accepts them.

        The call goes through Invoke-AACHttp: the module's pooled HttpClient
        (connections reused, not a TLS handshake per call), throttling (429)
        and server errors retried as Retry-After asks, dropped connections
        retried. Other failures throw, with the HTTP status in the
        exception's Data['StatusCode'] so callers can tell "not found" from
        "forbidden", and Azure's own message. -Uri may be a full URL or a path
        starting with '/' (https://management.azure.com is added).

        -Resource calls another Azure API with the same sign-in: the token
        audience, e.g. https://api.loganalytics.io for a Log Analytics query
        (Get-AACAccessToken -Resource). Its errors have the same shape.
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('Get', 'Post')]
        [string] $Method = 'Get',

        [Parameter(Mandatory)]
        [string] $Uri,

        [string] $Body,

        [string] $Resource = 'https://management.azure.com'
    )

    $request = @{ Method = $Method; Uri = $Uri; Resource = $Resource }
    if ($Body) { $request.Body = $Body }
    $content = (Invoke-AACHttp @request).Content
    if ([string]::IsNullOrWhiteSpace($content)) {
        return $null
    }
    ConvertFrom-Json -InputObject $content -AsHashtable -Depth 100
}
