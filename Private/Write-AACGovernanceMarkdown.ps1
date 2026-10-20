function Write-AACGovernanceMarkdown {
    <#
    .SYNOPSIS
        Writes Invoke-AACGovernanceAssessment's results as one Markdown page
        for a wiki - GitHub, or an Azure DevOps wiki - with the management
        group hierarchy as a Mermaid diagram and a table per area.
    .DESCRIPTION
        -Section is ordered: name -> @{ Note; Rows; Columns (the property
        names shown, in order) }. Each table shows the first -MaxRows rows
        (the HTML report and the objects have them all). -Hierarchy is the
        AAC.ManagementGroup rows, drawn as a Mermaid graph: GitHub renders
        ```mermaid blocks, an Azure DevOps wiki ::: mermaid blocks
        (-Flavor). Pipes and line breaks in values are escaped so tables
        hold.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Title,

        [System.Collections.IDictionary] $Fact = [ordered]@{},

        [string] $Headline = '',

        [object[]] $Tile = @(),

        [object[]] $Hierarchy = @(),

        [System.Collections.IDictionary] $Section = [ordered]@{},

        [ValidateSet('GitHub', 'AzureDevOps')]
        [string] $Flavor = 'GitHub',

        [ValidateRange(1, 5000)]
        [int] $MaxRows = 50
    )

    $cell = {
        param($Value)
        $text = if ($null -eq $Value) { '' } elseif ($Value -is [datetime]) { $Value.ToString('yyyy-MM-dd HH:mm') } elseif ($Value -is [bool]) { if ($Value) { 'Yes' } else { 'No' } } else { [string]$Value }
        ($text -replace '\r?\n', ' ' -replace '\|', '\|').Trim()
    }
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("# $Title")
    $lines.Add('')
    $lines.Add("_Written by Azure Admin Console on $((Get-Date).ToString('d MMMM yyyy HH:mm'))$(if ($Fact.Count) { ' - ' + (@($Fact.Keys | ForEach-Object { "$($_): $($Fact[$_])" }) -join ' - ') })._")
    $lines.Add('')
    if ($Headline) { $lines.Add("> $(& $cell $Headline)"); $lines.Add('') }
    if ($Tile.Count) {
        $lines.Add('| Measure | Value |'); $lines.Add('|---|---:|')
        foreach ($t in $Tile) { $lines.Add("| $(& $cell $t.Label) | $(& $cell $t.Value) |") }
        $lines.Add('')
    }

    # The hierarchy, as a Mermaid graph.
    if ($Hierarchy.Count) {
        $lines.Add('## Management group hierarchy'); $lines.Add('')
        $idOf = @{}
        $n = 0
        foreach ($h in $Hierarchy) { $n++; $idOf[[string]$h.ManagementGroup] = "mg$n" }
        $graph = [System.Collections.Generic.List[string]]::new()
        $graph.Add('graph TD')
        foreach ($h in $Hierarchy) {
            $label = "$($h.ManagementGroup)<br/>$($h.SubscriptionsBelow) sub(s)$(if ($h.PolicyAssignments) { " - $($h.PolicyAssignments) polic(ies)" })$(if ($h.RoleAssignments) { " - $($h.RoleAssignments) role(s)" })" -replace '"', "'"
            $graph.Add("    $($idOf[[string]$h.ManagementGroup])[""$label""]")
            if ($h.Parent -and $idOf.Contains([string]$h.Parent)) { $graph.Add("    $($idOf[[string]$h.Parent]) --> $($idOf[[string]$h.ManagementGroup])") }
        }
        if ($Flavor -eq 'AzureDevOps') { $lines.Add('::: mermaid'); foreach ($g in $graph) { $lines.Add($g) }; $lines.Add(':::') }
        else { $lines.Add('```mermaid'); foreach ($g in $graph) { $lines.Add($g) }; $lines.Add('```') }
        $lines.Add('')
    }

    foreach ($name in $Section.Keys) {
        $s = $Section[$name]
        $rows = @($s.Rows | Where-Object { $null -ne $_ })
        $lines.Add("## $name ($($rows.Count))"); $lines.Add('')
        if ($s.Contains('Note') -and $s.Note) { $lines.Add([string]$s.Note); $lines.Add('') }
        if (-not $rows.Count) { $lines.Add('_Nothing to show._'); $lines.Add(''); continue }
        $columns = @($s.Columns | Where-Object { $rows[0].PSObject.Properties[$_] })
        $lines.Add('| ' + ($columns -join ' | ') + ' |')
        $lines.Add('|' + (@($columns | ForEach-Object { '---' }) -join '|') + '|')
        foreach ($r in @($rows | Select-Object -First $MaxRows)) { $lines.Add('| ' + (@($columns | ForEach-Object { & $cell $r.$_ }) -join ' | ') + ' |') }
        if ($rows.Count -gt $MaxRows) { $lines.Add(''); $lines.Add("_The first $MaxRows of $($rows.Count): the HTML report and the objects have them all._") }
        $lines.Add('')
    }

    $folder = Split-Path -Path $Path -Parent
    if ($folder -and -not (Test-Path -LiteralPath $folder)) { $null = New-Item -ItemType Directory -Path $folder -Force }
    [System.IO.File]::WriteAllText($Path, ($lines -join "`n") + "`n", [System.Text.UTF8Encoding]::new($false))
}
