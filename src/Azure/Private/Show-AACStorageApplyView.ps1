function Show-AACStorageApplyView {
    <#
    .SYNOPSIS
        Renders what Deploy-AACStorageAccount applied, and its verification,
        as a Spectre.Console view.
    .DESCRIPTION
        Each change: Applied, Failed (with Azure's reason) or Skipped, and
        how long it took; then the verification - everything read again and
        compared: matches the configuration, or what still differs (what
        Azure changed by itself, a Modify policy say).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Deployment
    )

    $escape = { param($Text) [Spectre.Console.Markup]::Escape([string]$Text) }
    $glyph = Get-AACGlyph
    $table = [Spectre.Console.Table]::new()
    $table.Border = [Spectre.Console.TableBorder]::Rounded
    $table.BorderStyle = [Spectre.Console.Style]::Parse('grey42')
    $table.Expand = $true
    $table.Title = [Spectre.Console.TableTitle]::new("[bold]$($glyph.Bullet) Applied[/]")
    foreach ($column in 'Status', 'Resource', 'Change', 'Seconds', 'Detail') { $table.AddColumn([Spectre.Console.TableColumn]::new("[grey62]$column[/]")) | Out-Null }
    $colors = @{ Applied = 'green3'; Failed = 'red1'; Skipped = 'grey50' }
    foreach ($item in @($Deployment.Applied)) {
        $cells = @("[bold $($colors[$item.Status])]$(& $escape $item.Status)[/]", "[bold]$(& $escape $item.Resource)[/]", (& $escape $item.Action), "$($item.Seconds)", "[grey70]$(& $escape $item.Detail)[/]")
        [Spectre.Console.TableExtensions]::AddRow($table, [Spectre.Console.Rendering.IRenderable[]]@($cells | ForEach-Object { [Spectre.Console.Markup]::new($_) })) | Out-Null
    }
    [Spectre.Console.AnsiConsole]::Write($table)
    [Spectre.Console.AnsiConsole]::WriteLine()
    if ($Deployment.Status -eq 'Failed') { return }
    $left = @($Deployment.Verification)
    if (-not $left.Count) {
        Show-AACCallout Success -Title 'Verified' -Message "[bold green3]Verified.[/] [grey70]Read again, $(& $escape $Deployment.Name) matches the configuration: running this again changes nothing.[/]" -BorderColor 'green3' -AllowMarkup
    }
    else {
        $lines = @(foreach ($item in $left) {
                "[bold]$(& $escape $item.Resource)[/] [grey58]($(& $escape $item.Action))[/]"
                foreach ($difference in @($item.Differences)) { "  [orange1]~[/] $(& $escape $difference.Property): [white]$(& $escape $difference.Current)[/] [grey58]$($glyph.Arrow)[/] configured [white]$(& $escape $difference.Desired)[/]" }
            })
        Show-AACCallout Warning -Message "[bold orange1]Applied, but $($left.Count) resource(s) differ from the configuration when read again.[/] [grey70]Azure changed them by itself - a Modify or Append policy, or a setting the service adjusts. Running again would try to change them back.[/]`n$($lines -join "`n")"
    }
    [Spectre.Console.AnsiConsole]::WriteLine()
}
