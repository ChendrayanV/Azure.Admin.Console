function Show-AACJson {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        Shows JSON - or any PowerShell object, as JSON - at the console,
        indented and syntax-coloured in a panel, so an ARM template, a REST
        response or a resource's properties are easy to read.
    .DESCRIPTION
        Pipe in JSON text (an API response, a template file's content) or
        objects (Resource Graph rows, Invoke-RestMethod results, this
        module's output): it's shown indented, with property names, strings,
        numbers, true/false and null each in their own colour:

          ╭─ storage account ───────────────────────────────╮
          │ {                                               │
          │   "name": "stcontoso",                          │
          │   "location": "westeurope",                     │
          │   "properties": {                               │
          │     "minimumTlsVersion": "TLS1_2",              │
          │     "allowBlobPublicAccess": false              │
          │   }                                             │
          │ }                                               │
          ╰─────────────────────────────────────────────────╯

        Several objects piped in are shown as one JSON array. JSON text that
        isn't valid is shown as it is, with a warning. Long JSON is paged
        (any key for the next page, A for the rest; -NoPaging turns it off).
        Nothing is sent anywhere: it only formats what it's given.
    .PARAMETER InputObject
        JSON text, or objects to show as JSON.
    .PARAMETER Title
        The panel's title. Defaults to 'JSON'.
    .PARAMETER Depth
        How deep objects are converted to JSON (default 10). Ignored for JSON
        text.
    .PARAMETER PassThru
        Also pass the input on, unchanged.
    .PARAMETER NoPaging
        Show it all at once instead of a page at a time.
    .EXAMPLE
        Get-Content .\azuredeploy.json -Raw | Show-AACJson -Title 'ARM template'
        An ARM template, coloured.
    .EXAMPLE
        Invoke-RestMethod -Uri $uri -Headers $headers | Show-AACJson -Title 'Response'
        A REST response, as JSON.
    .EXAMPLE
        Show-AACDashboard -NoDisplay | Select-Object Status, Headline, Health | Show-AACJson
        Part of the dashboard object, as JSON.
    .OUTPUTS
        The input, with -PassThru.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [AllowNull()]
        [AllowEmptyString()]
        [object] $InputObject,

        [string] $Title = 'JSON',

        [ValidateRange(1, 100)]
        [int] $Depth = 10,

        [switch] $PassThru,

        [switch] $NoPaging
    )

    begin {
        trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }
        $items = [System.Collections.Generic.List[object]]::new()
    }
    process {
        $items.Add($InputObject)
        if ($PassThru) { $InputObject }
    }
    end {
        trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }
        $allText = $items.Count -and -not @($items | Where-Object { $_ -isnot [string] }).Count
        $json = if ($allText) {
            # JSON text (piped lines are one document): re-indented when it parses.
            $text = ($items -join "`n").Trim()
            try { ConvertFrom-Json -InputObject $text -AsHashtable -Depth 100 -NoEnumerate -ErrorAction Stop | ConvertTo-Json -Depth 100 }
            catch { Write-Warning "That isn't valid JSON, so it's shown as it is: $($_.Exception.Message)"; $text }
        }
        elseif ($items.Count -eq 1) { ConvertTo-Json -InputObject $items[0] -Depth $Depth }
        else { ConvertTo-Json -InputObject $items.ToArray() -Depth $Depth }
        if ($null -eq $json) { $json = 'null' }

        $panel = [Spectre.Console.Panel]::new([Spectre.Console.Markup]::new((ConvertTo-AACJsonMarkup -Json $json)))
        $panel.Border = [Spectre.Console.BoxBorder]::Rounded
        $panel.BorderStyle = [Spectre.Console.Style]::Parse('grey35')
        $panel.Header = [Spectre.Console.PanelHeader]::new(" [bold]$([Spectre.Console.Markup]::Escape($Title))[/] ")
        $panel.Expand = $true
        Invoke-AACPagedOutput -NoPaging:$NoPaging -ScriptBlock { [Spectre.Console.AnsiConsole]::Write($panel) }
    }
}
