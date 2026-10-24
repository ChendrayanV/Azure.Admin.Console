function ConvertTo-AACExceptionRecord {
    <#
    .SYNOPSIS
        Flattens one exception row - from a workspace's AppExceptions table
        or Application Insights' exceptions table - into an
        AAC.ApplicationInsightsException object.
    .DESCRIPTION
        Both schemas give the same properties. The details array (one entry
        per exception in the chain) becomes the outermost entry's message,
        type and severity level, the count of entries, and the top stack
        frame; custom properties become one "key=value; ..." column.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Row,

        [string] $Source
    )

    # A column by any of its names (workspace or classic schema).
    $get = {
        param([string[]] $Names)
        foreach ($name in $Names) {
            if ($Row.Contains($name) -and $null -ne $Row[$name] -and [string]$Row[$name] -ne '') { return $Row[$name] }
        }
        $null
    }
    # Dynamic columns arrive as JSON text.
    $parse = {
        param($Value)
        if ($Value -is [string] -and $Value.Trim() -match '^[\[{]') {
            try { return ConvertFrom-Json -InputObject $Value -AsHashtable -ErrorAction Stop } catch { return $Value }
        }
        $Value
    }
    $text = { param($Value) if ($null -eq $Value) { '' } else { [string]$Value } }
    $severityNames = @('Verbose', 'Information', 'Warning', 'Error', 'Critical')

    $time = & $get 'TimeGenerated', 'timestamp'
    $when = $null
    if ($time -is [datetime]) { $when = $time.ToUniversalTime() }
    elseif ($time) {
        $parsed = [datetimeoffset]::MinValue
        if ([datetimeoffset]::TryParse([string]$time, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$parsed)) { $when = $parsed.UtcDateTime }
    }
    $level = & $get 'SeverityLevel', 'severityLevel'
    $levelNumber = if ($null -ne $level -and [string]$level -match '^\d+$') { [int]$level } else { $null }

    $details = @(& $parse (& $get 'Details', 'details') | Where-Object { $_ -is [System.Collections.IDictionary] })
    $first = if ($details.Count) { $details[0] } else { @{} }
    $frame = $null
    if ($first.Contains('parsedStack') -and @($first['parsedStack']).Count) { $frame = @($first['parsedStack'])[0] }
    $stackTop = if ($frame -is [System.Collections.IDictionary]) {
        $at = & $text $frame['method']
        if ($frame['fileName']) { $at += " ($($frame['fileName'])$(if ($frame['line']) { ":$($frame['line'])" }))" }
        $at
    }
    else { '' }

    $properties = & $parse (& $get 'Properties', 'customDimensions')
    $propertyText = if ($properties -is [System.Collections.IDictionary]) {
        (@($properties.Keys | Sort-Object | ForEach-Object { "$_=$($properties[$_])" }) -join '; ')
    }
    else { & $text $properties }

    $type = & $text (& $get 'ExceptionType', 'type', 'OuterType', 'outerType')
    $message = & $text (& $get 'Message', 'message', 'OuterMessage', 'outerMessage', 'InnermostMessage', 'innermostMessage')
    [pscustomobject]@{
        PSTypeName            = 'AAC.ApplicationInsightsException'
        TimeGenerated         = $when
        Severity              = $(if ($null -ne $levelNumber -and $levelNumber -lt $severityNames.Count) { $severityNames[$levelNumber] } else { & $text $level })
        SeverityLevel         = $levelNumber
        ExceptionType         = $type
        Message               = $message
        OuterType             = & $text (& $get 'OuterType', 'outerType')
        OuterMessage          = & $text (& $get 'OuterMessage', 'outerMessage')
        InnermostType         = & $text (& $get 'InnermostType', 'innermostType')
        InnermostMessage      = & $text (& $get 'InnermostMessage', 'innermostMessage')
        DetailType            = & $text $first['type']
        DetailMessage         = & $text $first['message']
        DetailSeverityLevel   = & $text $first['severityLevel']
        DetailCount           = $details.Count
        StackTop              = $stackTop
        Method                = & $text (& $get 'Method', 'method', 'InnermostMethod', 'innermostMethod')
        Assembly              = & $text (& $get 'Assembly', 'assembly', 'InnermostAssembly', 'innermostAssembly')
        ProblemId             = & $text (& $get 'ProblemId', 'problemId')
        HandledAt             = & $text (& $get 'HandledAt', 'handledAt')
        OperationName         = & $text (& $get 'OperationName', 'operation_Name')
        OperationId           = & $text (& $get 'OperationId', 'operation_Id')
        AppRoleName           = & $text (& $get 'AppRoleName', 'cloud_RoleName', 'appName')
        AppRoleInstance       = & $text (& $get 'AppRoleInstance', 'cloud_RoleInstance')
        AppVersion            = & $text (& $get 'AppVersion', 'application_Version')
        ClientType            = & $text (& $get 'ClientType', 'client_Type')
        ClientCountryOrRegion = & $text (& $get 'ClientCountryOrRegion', 'client_CountryOrRegion')
        ClientCity            = & $text (& $get 'ClientCity', 'client_City')
        SdkVersion            = & $text (& $get 'SDKVersion', 'sdkVersion')
        ItemCount             = $(if ((& $get 'ItemCount', 'itemCount') -as [int]) { [int](& $get 'ItemCount', 'itemCount') } else { 1 })
        CustomProperties      = $propertyText
        Source                = $Source
        ResourceId            = & $text (& $get '_ResourceId')
    }
}
