function Show-AACError {
    <#
    .SYNOPSIS
        Shows a command's failure as a Spectre.Console panel, and returns the
        error record the command stops with.
    .DESCRIPTION
        Every exported command starts with

          trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

        A stopped pipeline (Select-Object -First, Ctrl+C) never reaches this
        function: the trap returns, because rethrowing that exception would
        stop the caller's whole script instead of just this command.

        so a failure anywhere inside it - its own checks, Azure, an export -
        ends the same way. At an interactive console, a red panel:

          ╭─ ✗ Show-AACCost failed ─────────────────────────────────────────╮
          │ Azure refused the request (403): The client ... does not have   │
          │ authorization to perform action 'Microsoft.CostManagement/...'  │
          │                                                                 │
          │ Step   Reading the costs of Contoso Prod                        │
          │ Fix    Your account needs a role that allows this ...           │
          ╰─────────────────────────────────────────────────────────────────╯

        the step is the progress line that was running (Invoke-AACProgress
        records it on the exception), and the fix a hint: the one the code
        that raised the error put in the exception's Data['AACHint'] (e.g.
        the tables that do exist), else one for the usual causes: not signed
        in, no access, not found, throttling, the network, a file that's
        open elsewhere.

        Then the command stops with a clean terminating error: its own name
        and the message, pointing at the caller's line rather than a line
        inside the module - so try/catch, $Error and -ErrorVariable work as
        with any cmdlet, and scripts and CI logs (no panel there) get the
        same message.

        An error the module didn't mean to raise - a null, a missing property
        or index under strict mode - is a bug in the module. Its message then
        says so, with where it happened and where to report it, instead of
        the bare .NET message.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.ErrorRecord])]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorRecord] $ErrorRecord,

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCmdlet] $Cmdlet
    )

    $exception = $ErrorRecord.Exception
    $command = $Cmdlet.MyInvocation.MyCommand.Name

    # Already handled by a command this one called: pass it on as it is.
    if ($exception.Data.Contains('AACHandled')) {
        return $ErrorRecord
    }

    # Errors PowerShell raises for code, not for circumstances: a bug here.
    $bugIds = 'PropertyNotFoundStrict', 'VariableIsUndefined', 'InvokeMethodOnNull', 'NullArray', 'IndexOutOfRange',
    'MethodNotFound', 'CannotIndex', 'NullArrayIndex', 'InvalidCastFromStringToInteger', 'ParameterBindingFailed'
    $errorId = ([string]$ErrorRecord.FullyQualifiedErrorId -split ',')[0]
    $isBug = $errorId -in $bugIds -or $exception -is [System.NullReferenceException] -or
    $exception -is [System.IndexOutOfRangeException] -or $exception -is [System.InvalidCastException] -or
    $exception -is [System.Management.Automation.PropertyNotFoundException]

    $status = if ($exception.Data.Contains('StatusCode')) { [int]$exception.Data['StatusCode'] } else { 0 }
    $step = if ($exception.Data.Contains('AACStep')) { [string]$exception.Data['AACStep'] } else { '' }
    $message = $exception.Message.Trim()

    # Where in the module it happened: the innermost frame of the script
    # stack, relative to the module folder.
    $where = ''
    $frame = @("$($ErrorRecord.ScriptStackTrace)" -split '\r?\n' | Where-Object { $_ -match '^at (.+?), (.+): line (\d+)$' } | Select-Object -First 1)
    if ($frame.Count -and $frame[0] -match '^at (.+?), (.+): line (\d+)$') {
        $file = $Matches[2]
        if ($script:AACModuleRoot -and $file.StartsWith($script:AACModuleRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            $file = $file.Substring($script:AACModuleRoot.Length).TrimStart('\', '/')
        }
        $where = '{0}:{1}' -f $file, $Matches[3]
    }

    $version = $Cmdlet.MyInvocation.MyCommand.Module.Version
    $issues = 'https://github.com/ChendrayanV/Azure.Admin.Console/issues'
    $hint = if ($exception.Data.Contains('AACHint') -and $exception.Data['AACHint']) {
        # The code that raised the error knows best what to do about it.
        [string]$exception.Data['AACHint']
    }
    elseif ($isBug) {
        "This is a bug in Azure.Admin.Console $version, not in your Azure setup. Please report it at $issues with this message."
    }
    elseif ($message -match 'Connect-AAC') { '' }
    elseif ($status -eq 401) { 'Azure no longer accepts the sign-in. Run Connect-AAC again.' }
    elseif ($status -eq 403) { 'Your account needs a role that allows this: Reader on the subscriptions for most commands, Cost Management Reader for Show-AACCost, Log Analytics Reader for Invoke-AACApplicationInsightQuery; permission to read groups in Entra ID for Get-AACEntraGroupMembership.' }
    elseif ($status -eq 404) { 'Check the name, and the subscription (-SubscriptionId) it is in.' }
    elseif ($status -eq 429) { 'Azure is throttling requests. Wait a minute, then try again - or narrow the scope with -SubscriptionId.' }
    elseif ($status -ge 500) { 'Azure had a problem of its own. Try again in a few minutes.' }
    elseif ($exception -is [System.Net.Http.HttpRequestException] -or $exception.InnerException -is [System.Net.Http.HttpRequestException] -or $exception -is [System.Net.Sockets.SocketException]) {
        'Azure could not be reached. Check the network connection and proxy.'
    }
    elseif ($exception -is [System.IO.IOException] -or $exception -is [System.UnauthorizedAccessException]) {
        'The file could not be written. Close it if it is open (a PDF viewer, Excel), or choose another path.'
    }
    else { '' }

    $title = if ($isBug) {
        "Azure.Admin.Console hit an internal error: $message"
    }
    elseif ($status) {
        "Azure refused the request ($status): $message"
    }
    else {
        $message
    }

    if (Test-AACErrorPanel -Cmdlet $Cmdlet) {
        $escape = { param([string] $Text) [Spectre.Console.Markup]::Escape($Text) }
        $grid = [Spectre.Console.Grid]::new()
        $labelColumn = [Spectre.Console.GridColumn]::new()
        $labelColumn.NoWrap = $true
        $grid.AddColumn($labelColumn) | Out-Null
        $grid.AddColumn([Spectre.Console.GridColumn]::new()) | Out-Null
        $addRow = {
            param([string] $Label, [string] $Value, [string] $Style)
            $grid.AddRow([Spectre.Console.Rendering.IRenderable[]]@(
                    [Spectre.Console.Markup]::new("[grey58]$Label[/]"),
                    [Spectre.Console.Markup]::new("[$Style]$(& $escape $Value)[/]"))) | Out-Null
        }
        if ($step) { & $addRow 'Step' $step 'grey85' }
        if ($isBug -and $where) { & $addRow 'Where' $where 'grey58' }
        if ($hint) { & $addRow 'Fix' $hint 'deepskyblue1' }

        $body = [System.Collections.Generic.List[Spectre.Console.Rendering.IRenderable]]::new()
        $body.Add([Spectre.Console.Markup]::new("[red1]$(& $escape $title)[/]"))
        if ($step -or ($isBug -and $where) -or $hint) {
            $body.Add([Spectre.Console.Text]::new(''))
            $body.Add($grid)
        }
        $panel = [Spectre.Console.Panel]::new([Spectre.Console.Rows]::new($body))
        $panel.Border = [Spectre.Console.BoxBorder]::Rounded
        $panel.BorderStyle = [Spectre.Console.Style]::Parse('red1')
        $panel.Header = [Spectre.Console.PanelHeader]::new("[red1] $((Get-AACGlyph).Cross) $(& $escape $command) failed [/]")
        $panel.Expand = $true
        [Spectre.Console.AnsiConsole]::Write($panel)
    }

    # The record the command stops with: the message a script or log needs
    # on its own, the original exception inside.
    $text = $title
    if ($isBug -and $where) { $text += " (at $where)" }
    if ($hint) { $text += " $hint" }
    $clean = [System.Exception]::new($text, $exception)
    foreach ($key in $exception.Data.Keys) { $clean.Data[$key] = $exception.Data[$key] }
    $clean.Data['AACHandled'] = $true

    $category = if ($isBug) { [System.Management.Automation.ErrorCategory]::NotSpecified }
    elseif ($status -in 401, 403) { [System.Management.Automation.ErrorCategory]::PermissionDenied }
    elseif ($status -eq 404) { [System.Management.Automation.ErrorCategory]::ObjectNotFound }
    elseif ($status) { [System.Management.Automation.ErrorCategory]::ConnectionError }
    else { $ErrorRecord.CategoryInfo.Category }
    $id = if ($isBug) { 'InternalError' } elseif ($status) { "AzureRequestFailed$status" } else { 'CommandFailed' }

    [System.Management.Automation.ErrorRecord]::new($clean, $id, $category, $ErrorRecord.TargetObject)
}
