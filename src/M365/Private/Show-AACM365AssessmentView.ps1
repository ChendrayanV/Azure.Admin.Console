function Show-AACM365AssessmentView {
    <#
    .SYNOPSIS
        Renders Invoke-AACM365Assessment's result as a Spectre.Console view.
    .DESCRIPTION
        The scope; tiles (Secure Score, MFA registration, Conditional Access,
        Global Administrators, sharing, devices); the key settings; the
        Conditional Access policies; the privileged role assignments; what
        Graph refused, with the permission it needs; and the Critical, High
        and Medium findings with what to do. Wrap the call in
        Invoke-AACPagedOutput to page it.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Assessment,

        [System.Collections.IDictionary] $Scope,

        [int] $Top = 15
    )

    $escape = { param($Text) [Spectre.Console.Markup]::Escape([string]$Text) }
    $glyph = Get-AACGlyph
    $stats = $Assessment.Stats
    $color = @{ Critical = 'red1'; High = 'red1'; Medium = 'orange1'; Low = 'deepskyblue1'; Info = 'grey62' }
    $statusColor = @{ Good = 'green3'; Warning = 'red1'; Review = 'orange1'; Info = 'grey70'; Unknown = 'grey50' }
    $newTable = {
        param([string] $TitleText, [string[]] $Headers, [string[]] $Right = @())
        $t = [Spectre.Console.Table]::new(); $t.Border = [Spectre.Console.TableBorder]::Rounded; $t.BorderStyle = [Spectre.Console.Style]::Parse('deepskyblue3_1'); $t.Expand = $true
        if ($TitleText) { $t.Title = [Spectre.Console.TableTitle]::new($TitleText) }
        foreach ($header in $Headers) { $column = [Spectre.Console.TableColumn]::new("[grey62]$header[/]"); if ($header -in $Right) { $column.Alignment = [Spectre.Console.Justify]::Right }; $t.AddColumn($column) | Out-Null }
        $t
    }
    $addRow = { param($Table, [string[]] $Cells) [Spectre.Console.TableExtensions]::AddRow($Table, [Spectre.Console.Rendering.IRenderable[]]@($Cells | ForEach-Object { [Spectre.Console.Markup]::new($_) })) | Out-Null }
    $title = { param([string] $Text, [string] $Note) "[bold]$($glyph.Bullet) $Text[/]$(if ($Note) { " [grey58]$($glyph.Dot) $Note[/]" })" }
    $write = { param($Table) [Spectre.Console.AnsiConsole]::Write($Table); [Spectre.Console.AnsiConsole]::WriteLine() }
    $percentColor = { param($Value) if ($null -eq $Value) { 'grey50' } elseif ($Value -ge 70) { 'green3' } elseif ($Value -ge 40) { 'orange1' } else { 'red1' } }

    $facts = [System.Collections.Generic.List[string]]::new()
    if ($stats.Tenant) { $facts.Add("[white]$(& $escape $stats.Tenant)[/]") }
    if ($script:AACSession) { $facts.Add((& $escape $script:AACSession.Account)) }
    if ($Scope) { foreach ($key in $Scope.Keys) { $facts.Add("$(& $escape $key): $(& $escape $Scope[$key])") } }
    $facts.Add((Get-Date).ToString('d MMM yyyy HH:mm'))
    Write-AACMarkup "[grey58]$($facts -join " $($glyph.Dot) ")[/]"
    foreach ($line in @($Assessment.Notices)) { Write-AACStatusLine Warning $line }
    [Spectre.Console.AnsiConsole]::WriteLine()

    Show-AACTileRow -Tile @(
        @{ Value = $(if ($null -ne $stats.SecureScore) { "$($stats.SecureScore)%" } else { '-' }); Caption = 'Secure Score'; Color = (& $percentColor $stats.SecureScore) }
        @{ Value = $(if ($null -ne $stats.MfaRegistered) { "$($stats.MfaRegistered)%" } else { '-' }); Caption = "MFA registered ($($stats.AdminsWithoutMfa) admins without)"; Color = $(if ($stats.AdminsWithoutMfa) { 'red1' } else { & $percentColor $stats.MfaRegistered }) }
        @{ Value = "$($stats.ConditionalAccessOn)/$($stats.ConditionalAccess)"; Caption = 'Conditional Access on'; Color = 'deepskyblue1' }
        @{ Value = '{0:N0}' -f $stats.GlobalAdmins; Caption = 'Global Administrators'; Color = $(if ($stats.GlobalAdmins -gt 5 -or $stats.GlobalAdmins -lt 2) { 'orange1' } else { 'green3' }) }
        @{ Value = '{0:N0}' -f $stats.ManagedDevices; Caption = "devices ($($stats.NonCompliant) non-compliant)"; Color = $(if ($stats.NonCompliant) { 'orange1' } else { 'green3' }) }
        @{ Value = '{0:N0}' -f ($stats.Critical + $stats.High); Caption = "critical and high findings"; Color = $(if ($stats.Critical + $stats.High) { 'red1' } else { 'green3' }) }
    )
    [Spectre.Console.AnsiConsole]::WriteLine()

    $keySettings = @($Assessment.Settings | Where-Object { $_.Status -in 'Warning', 'Review', 'Good' -and $_.Area -ne 'Tenant' })
    if ($keySettings.Count) {
        $table = & $newTable (& $title 'Security settings' 'warnings first') @('Area', 'Setting', 'Value')
        foreach ($s in $keySettings | Sort-Object -Property @{ Expression = { @{ Warning = 0; Review = 1; Good = 2 }[$_.Status] } }, Area | Select-Object -First 25) { & $addRow $table @("[grey70]$(& $escape $s.Area)[/]", (& $escape $s.Setting), "[$($statusColor[$s.Status])]$(& $escape $s.Value)[/]") }
        & $write $table
    }

    $ca = @($Assessment.ConditionalAccess)
    if ($ca.Count) {
        $table = & $newTable (& $title 'Conditional Access' "$($ca.Count) policies") @('Policy', 'State', 'Users', 'Applications', 'Grant')
        foreach ($p in $ca | Select-Object -First $Top) { & $addRow $table @("[white]$(& $escape $p.Policy)[/]", $(switch ($p.State) { 'On' { '[green3]On[/]' } 'Report-only' { '[orange1]Report-only[/]' } default { '[grey50]Off[/]' } }), (& $escape $p.Users), (& $escape $p.Applications), (& $escape $p.Grant)) }
        & $write $table
    }

    $privileged = @($Assessment.RoleAssignments | Where-Object Privileged -EQ 'Yes')
    if ($privileged.Count) {
        $table = & $newTable (& $title 'Privileged role assignments' "$(@($privileged.PrincipalId | Select-Object -Unique).Count) accounts") @('Role', 'Principal', 'Assignment', 'MFA')
        foreach ($r in $privileged | Select-Object -First $Top) { & $addRow $table @((& $escape $r.Role), "[white]$(& $escape $(if ($r.UserPrincipalName) { $r.UserPrincipalName } else { $r.Principal }))[/]", $(if ($r.Assignment -eq 'Active') { '[orange1]Active[/]' } else { '[green3]Eligible[/]' }), $(switch ($r.MfaRegistered) { 'Yes' { '[green3]Yes[/]' } 'No' { '[red1]No[/]' } default { '[grey50]-[/]' } })) }
        & $write $table
    }

    $refused = @($Assessment.Permissions | Where-Object Status -EQ 'Not read')
    if ($refused.Count) {
        $table = & $newTable (& $title 'Not read' 'Graph refused these - grant the permission (admin consent) to the app you sign in with') @('Data', 'Permission', 'Why')
        foreach ($p in $refused) { & $addRow $table @((& $escape $p.Data), "[orange1]$(& $escape $p.Permission)[/]", "[grey62]$(& $escape ($p.Reason -replace '\s+', ' '))[/]") }
        & $write $table
    }

    $serious = @($Assessment.Findings | Where-Object { $_.Severity -in 'Critical', 'High', 'Medium' })
    if ($serious.Count) {
        Write-AACMarkup (& $title 'Findings' "Critical, High and Medium: $($serious.Count) ($($stats.Low) low)")
        foreach ($f in $serious | Select-Object -First 30) {
            Write-AACMarkup "  [$($color[$f.Severity])]$($f.Severity.ToUpperInvariant().PadRight(8))[/] [white]$(& $escape $f.Finding)[/] [grey62]$(& $escape $f.Item)[/] [grey42]$(& $escape $f.Area)[/]"
            Write-AACMarkup "           [grey85]$(& $escape $f.Detail)[/]"
            if ($f.Recommendation) { Write-AACMarkup "           [grey50]$($glyph.Arrow) $(& $escape $f.Recommendation)[/]" }
        }
        if ($serious.Count -gt 30) { Write-AACMarkup "  [grey50]... and $($serious.Count - 30) more: -HtmlPath has them all.[/]" }
        [Spectre.Console.AnsiConsole]::WriteLine()
    }
    Write-AACMarkup '[grey42]-HtmlPath writes the tabbed report (every setting, policy, role, user, device and Secure Score control, with row details); -CsvPath a CSV per table; -PassThru (or a pipe) returns the object.[/]'
}
