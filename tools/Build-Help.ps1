<#
    Builds the module's help with Microsoft.PowerShell.PlatyPS (1.0 or later):

      docs\<Command>.md                        one PlatyPS page per command
      en-US\Azure.Admin.Console-help.xml       MAML help, for Get-Help
      docs\Azure.Admin.Console.md              the command index
      docs\about_Azure.Admin.Console.md        a readable copy of the about topic

    The comment-based help in Public\*.ps1 stays the one place help is
    written. PlatyPS reads it (New-CommandHelp), this script tidies what
    PlatyPS can't know from comment-based help, and PlatyPS writes the
    Markdown and the MAML:

      - examples: the help's convention is the code, then one line saying
        what it does; PlatyPS sees one block of text, so the code is put in
        a powershell fence and the last line kept as the explanation;
      - lines indented by two or more spaces (aligned tables, the sketches
        of each console view) become fenced text blocks, keeping alignment;
      - parameter defaults are the declared expressions, not PlatyPS's
        guess; outputs come from .OUTPUTS only, without placeholders;
      - Get-Help -Online and the related links point at the page on GitHub;
      - no aliases placeholder, a fixed en-US locale and no ms.date, so the
        pages only change when the help does (CI checks docs\ is current).

    Run by build.ps1 -Task Docs in a pwsh process of its own: PlatyPS loads
    YamlDotNet, which must not meet another version of it in the build's
    session. PlatyPS is needed only to build - not by the installed module.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $ModuleManifest,
    [Parameter(Mandatory)] [string] $DocsPath,
    [Parameter(Mandatory)] [string] $HelpPath
)

$ErrorActionPreference = 'Stop'
if (-not (Get-Module -Name Microsoft.PowerShell.PlatyPS -ListAvailable | Where-Object Version -ge '1.0.0')) {
    throw 'Building the help needs Microsoft.PowerShell.PlatyPS 1.0 or later: Install-PSResource Microsoft.PowerShell.PlatyPS -Scope CurrentUser'
}
Import-Module Microsoft.PowerShell.PlatyPS -MinimumVersion 1.0.0
$module = Import-Module $ModuleManifest -Force -PassThru
$moduleName = $module.Name
$projectUri = ([string]$module.ProjectUri).TrimEnd('/')

# Comment-based help text -> Markdown. Lines indented by two or more spaces
# become fenced text blocks so they keep their alignment; everything else is
# ordinary paragraphs, with <, > and * escaped.
function ConvertTo-HelpMarkdown([string] $Text) {
    $escape = { param([string] $Line) $Line -replace '([<>*])', '\$1' }
    $out = [System.Collections.Generic.List[string]]::new()
    $lines = @(($Text -replace "`r", '').Trim("`n") -split "`n")
    $inBlock = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i].TrimEnd()
        $indented = $line -match '^\s{2,}\S'
        if ($indented -and -not $inBlock) {
            if ($out.Count -and $out[-1] -ne '') { $out.Add('') }
            $out.Add('```text')
            $inBlock = $true
        }
        elseif ($inBlock -and -not $indented) {
            # A blank line inside a block ends it only when the next
            # non-blank line isn't indented too.
            $next = if ($i + 1 -lt $lines.Count) { @($lines[($i + 1)..($lines.Count - 1)] | Where-Object { $_.Trim() }) | Select-Object -First 1 }
            if ($line -eq '' -and $next -match '^\s{2,}\S') {
                $out.Add('')
                continue
            }
            $out.Add('```')
            $inBlock = $false
            if ($line -ne '') { $out.Add('') }
        }
        $out.Add($(if ($inBlock) { $line } else { & $escape $line }))
    }
    if ($inBlock) { $out.Add('```') }
    $out -join "`n"
}

# A paragraph wrapped over several lines -> one line.
function ConvertTo-OneLine([string] $Text) {
    (($Text.Trim() -split '\s*\r?\n\s*') -join ' ')
}

# Plain text of each command, for the MAML: Get-Help shows MAML text as it
# is, so it gets the help as written rather than Markdown.
$plain = @{}
function ConvertTo-PlainText([string] $Text) { (($Text -replace "`r", '').Trim("`n")).TrimEnd() }

$commands = @(Get-Command -Module $moduleName -CommandType Function | Sort-Object Name)
$helps = foreach ($command in $commands) {
    $source = $command.ScriptBlock.Ast.GetHelpContent()
    if (-not $source) { throw "$($command.Name) has no comment-based help." }
    $help = New-CommandHelp -CommandInfo $command

    # PlatyPS writes one MAML file per module name - so set it.
    $help.ModuleName = $moduleName
    $help.Metadata['Module Name'] = $moduleName
    # PlatyPS also groups by help file name, case and all ('-Help' from its
    # defaults, '-help' from .EXTERNALHELP): one name for every command.
    $help.ExternalHelpFile = "$moduleName-help.xml"
    $help.Locale = [cultureinfo]::GetCultureInfo('en-US')
    $help.Metadata['Locale'] = 'en-US'
    $help.Metadata.Remove('ms.date')
    $help.Metadata['external help file'] = "$moduleName-help.xml"
    $help.Aliases = 'This command has no aliases.'
    $help.AliasHeaderFound = $true

    # Get-Help -Online and the related links go to the page on GitHub.
    $online = "$projectUri/blob/main/docs/$($command.Name).md"
    $help.OnlineVersionUrl = $online
    $help.Metadata['HelpUri'] = $online
    $help.RelatedLinks.Clear()
    $help.RelatedLinks.Add([Microsoft.PowerShell.PlatyPS.Model.Links]::new($online, 'Online version'))
    $help.RelatedLinks.Add([Microsoft.PowerShell.PlatyPS.Model.Links]::new("$projectUri/blob/main/docs/about_$moduleName.md", "about_$moduleName"))

    $help.Synopsis = ConvertTo-OneLine $source.Synopsis
    $plain[$command.Name] = @{
        Description = ConvertTo-PlainText $source.Description
        Notes       = $(if ($source.Notes) { ConvertTo-PlainText $source.Notes } else { '' })
        Parameters  = @{}
        Defaults    = @{}
        Examples    = [System.Collections.Generic.List[object]]::new()
    }
    $help.Description = ConvertTo-HelpMarkdown $source.Description

    # Examples: code in a fence, the closing sentence as the explanation.
    $help.Examples.Clear()
    $number = 0
    foreach ($text in $source.Examples) {
        $number++
        $lines = @(($text -replace "`r", '').Trim() -split "`n")
        $code = $lines
        $remark = ''
        if ($lines.Count -gt 1 -and $lines[-1] -cmatch '^[A-Z][a-z]' -and $lines[-1] -cnotmatch '^[A-Z][a-z]+-[A-Z]') {
            $code = $lines[0..($lines.Count - 2)]
            $remark = $lines[-1]
        }
        $body = "``````powershell`n$(($code | ForEach-Object { $_.TrimEnd() }) -join "`n")`n``````"
        if ($remark) { $body += "`n`n$(ConvertTo-HelpMarkdown $remark)" }
        $help.Examples.Add([Microsoft.PowerShell.PlatyPS.Model.Example]::new("Example $number", $body))
        $plain[$command.Name].Examples.Add(@{ Code = (($code | ForEach-Object { $_.TrimEnd() }) -join "`n"); Remark = $remark })
    }

    # Parameters: the help's own text and the declared default.
    $declared = @{}
    foreach ($p in @($command.ScriptBlock.Ast.Body.ParamBlock.Parameters)) {
        $declared[$p.Name.VariablePath.UserPath] = $p
    }
    foreach ($parameter in $help.Parameters) {
        $text = $source.Parameters[$parameter.Name.ToUpperInvariant()]
        $parameter.Description = if ($text) { ConvertTo-HelpMarkdown $text } else { '' }
        $plain[$command.Name].Parameters[$parameter.Name] = if ($text) { ConvertTo-PlainText $text } else { '' }
        $ast = $declared[$parameter.Name]
        $parameter.DefaultValue = if ($ast -and $ast.DefaultValue) { $ast.DefaultValue.Extent.Text }
        elseif ($parameter.Type -like '*SwitchParameter') { 'False' }
        else { 'None' }
        $plain[$command.Name].Defaults[$parameter.Name] = $parameter.DefaultValue
    }

    # Outputs: what .OUTPUTS says, nothing guessed.
    $help.Outputs.Clear()
    foreach ($output in @($source.Outputs | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
        $help.Outputs.Add([Microsoft.PowerShell.PlatyPS.Model.InputOutput]::new((ConvertTo-OneLine $output), ''))
    }
    $help.Inputs.Clear()
    $help.Notes = if ($source.Notes) { ConvertTo-HelpMarkdown $source.Notes } else { '' }
    $help
}

# --- Markdown: docs\<Command>.md ----------------------------------------------------
New-Item -ItemType Directory -Path $DocsPath -Force | Out-Null
$staging = Join-Path ([System.IO.Path]::GetTempPath()) "aac-help-$([guid]::NewGuid().ToString('n'))"
try {
    $written = @($helps | Export-MarkdownCommandHelp -OutputFolder $staging -Force)
    foreach ($file in $written) {
        # PlatyPS writes a folder per module; docs\ is flat.
        $text = (Get-Content -LiteralPath $file.FullName -Raw) -replace "`r`n", "`n"
        [System.IO.File]::WriteAllText((Join-Path $DocsPath $file.Name), $text.TrimEnd() + "`n", [System.Text.UTF8Encoding]::new($false))
        Write-Host "    $($file.Name)"
    }

    # --- MAML: en-US\Azure.Admin.Console-help.xml ---------------------------------------
    # The same help as plain text. PlatyPS's MAML export puts a whole
    # example in its introduction, so each example is then rewritten the
    # way Get-Help lays one out: the code, then the remarks.
    foreach ($help in $helps) {
        $text = $plain[$help.Title]
        $help.Description = $text.Description
        $help.Notes = $text.Notes
        foreach ($parameter in $help.Parameters) { $parameter.Description = $text.Parameters[$parameter.Name] }
    }
    $mamlFiles = @($helps | Export-MamlCommandHelp -OutputFolder (Join-Path $staging 'maml') -Force)
    if ($mamlFiles.Count -ne 1) { throw "PlatyPS wrote $($mamlFiles.Count) MAML files; expected one for $moduleName." }
    $mamlFile = $mamlFiles[0]
    $xml = [xml](Get-Content -LiteralPath $mamlFile.FullName -Raw)
    $ns = [System.Xml.XmlNamespaceManager]::new($xml.NameTable)
    $ns.AddNamespace('command', 'http://schemas.microsoft.com/maml/dev/command/2004/10')
    $ns.AddNamespace('maml', 'http://schemas.microsoft.com/maml/2004/10')
    $ns.AddNamespace('dev', 'http://schemas.microsoft.com/maml/dev/2004/10')
    foreach ($commandNode in $xml.SelectNodes('//command:command', $ns)) {
        $name = $commandNode.SelectSingleNode('command:details/command:name', $ns).InnerText
        # PlatyPS leaves out the default values; Get-Help shows them.
        foreach ($parameterNode in $commandNode.SelectNodes('command:parameters/command:parameter', $ns)) {
            $parameterName = $parameterNode.SelectSingleNode('maml:name', $ns).InnerText
            $default = $plain[$name].Defaults[$parameterName]
            if ($default -and $default -ne 'None') {
                $node = $parameterNode.SelectSingleNode('dev:defaultValue', $ns)
                if (-not $node) {
                    $node = $xml.CreateElement('dev', 'defaultValue', 'http://schemas.microsoft.com/maml/dev/2004/10')
                    $null = $parameterNode.AppendChild($node)
                }
                $node.InnerText = $default
            }
        }
        $examples = @($commandNode.SelectNodes('command:examples/command:example', $ns))
        for ($i = 0; $i -lt $examples.Count; $i++) {
            $example = $plain[$name].Examples[$i]
            $node = $examples[$i]
            $node.SelectSingleNode('maml:introduction', $ns).RemoveAll()
            $node.SelectSingleNode('dev:code', $ns).InnerText = $example.Code
            $remarks = $node.SelectSingleNode('dev:remarks', $ns)
            $remarks.RemoveAll()
            if ($example.Remark) {
                $para = $xml.CreateElement('maml', 'para', 'http://schemas.microsoft.com/maml/2004/10')
                $para.InnerText = $example.Remark
                $null = $remarks.AppendChild($para)
            }
        }
    }
    New-Item -ItemType Directory -Path $HelpPath -Force | Out-Null
    $target = Join-Path $HelpPath "$moduleName-help.xml"
    $settings = [System.Xml.XmlWriterSettings]::new()
    $settings.Indent = $true
    $settings.Encoding = [System.Text.UTF8Encoding]::new($false)
    $settings.NewLineChars = "`n"
    $writer = [System.Xml.XmlWriter]::Create($target, $settings)
    try { $xml.Save($writer) } finally { $writer.Dispose() }
    $count = @($xml.SelectNodes('//command:command', $ns)).Count
    if ($count -ne $commands.Count) { throw "The MAML help has $count commands; expected $($commands.Count)." }
    Write-Host "    $(Split-Path $HelpPath -Leaf)\$moduleName-help.xml ($count commands)"
}
finally {
    Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction Ignore
}

# --- about_ topics: the .help.txt in en-US is the source (it is what
# Get-Help about_Azure.Admin.Console shows); docs\ gets a readable copy.
foreach ($about in @(Get-ChildItem -Path $HelpPath -Filter 'about_*.help.txt' -File)) {
    $name = $about.Name -replace '\.help\.txt$', ''
    $body = "# $name`n`n[$moduleName]($moduleName.md)`n`n``````text`n$((Get-Content -LiteralPath $about.FullName -Raw).TrimEnd())`n```````n"
    [System.IO.File]::WriteAllText((Join-Path $DocsPath "$name.md"), $body, [System.Text.UTF8Encoding]::new($false))
    Write-Host "    $name.md"
}

# --- The index: docs\Azure.Admin.Console.md ------------------------------------------
$manifest = Import-PowerShellDataFile $ModuleManifest
$index = [System.Collections.Generic.List[string]]::new()
$index.Add("# $moduleName $($manifest.ModuleVersion)")
$index.Add('')
$index.Add($manifest.Description)
$index.Add('')
$index.Add("Start with [about_$moduleName](about_$moduleName.md), or ``Get-Help about_$moduleName`` once the module is imported. Every command also has full help in PowerShell: ``Get-Help <command> -Full``.")
$index.Add('')
$index.Add('## Commands')
$index.Add('')
$index.Add('| Command | Synopsis |')
$index.Add('|---|---|')
foreach ($help in $helps) {
    $index.Add("| [$($help.Title)]($($help.Title).md) | $($help.Synopsis -replace '\|', '\|') |")
}
[System.IO.File]::WriteAllText((Join-Path $DocsPath "$moduleName.md"), ($index -join "`n") + "`n", [System.Text.UTF8Encoding]::new($false))
Write-Host "    $moduleName.md"
