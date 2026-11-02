function ConvertFrom-AACHuntingQueryYaml {
    <#
    .SYNOPSIS
        Reads one hunting query file from the Azure-Sentinel repository.
    .DESCRIPTION
        No YAML module: these files are simple and regular, so each top-level
        key is found at the start of its line and its block is every indented
        line after it. Only what a hunting query needs is read: id, name,
        description, tactics, relevantTechniques, the dataTypes of
        requiredDataConnectors, query and version.

        Many files are stubs left behind when content moved into a solution:
        an id, a name and a description saying where the query went. A stub
        comes back with MovedTo, the path inside the repository, and no Query.

        The id must be a GUID: it becomes part of the Azure Resource Manager
        path a query is deployed to, and with -YamlSource the file can come
        from anywhere.

        Returns @{ Id; Name; Description; Tactics; Techniques; DataTypes;
        Query; Version; MovedTo }, or nothing when the file has no such id, or
        neither a query nor a new location.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text
    )

    $blocks = @{}
    $current = $null
    foreach ($line in ($Text.TrimStart([char]0xFEFF) -replace "`r`n", "`n") -split "`n") {
        if ($line -match '^([A-Za-z][\w-]*):\s*(.*)$') {
            $current = $Matches[1]
            $blocks[$current] = @{ Head = $Matches[2].Trim(); Lines = [System.Collections.Generic.List[string]]::new() }
        }
        elseif ($current -and $line -notmatch '^#') { $blocks[$current].Lines.Add($line) }
    }
    $unquote = {
        param([string] $Value)
        if ($Value.Length -ge 2 -and (($Value[0] -eq "'" -and $Value[-1] -eq "'") -or ($Value[0] -eq '"' -and $Value[-1] -eq '"'))) { $Value.Substring(1, $Value.Length - 2) } else { $Value }
    }
    $scalar = {
        param([string] $Key)
        if (-not $blocks.Contains($Key)) { return '' }
        $block = $blocks[$Key]
        if ($block.Head -match '^[|>][-+]?$') {
            $used = @($block.Lines | Where-Object { $_.Trim() })
            if (-not $used.Count) { return '' }
            $indent = ($used | ForEach-Object { $_.Length - $_.TrimStart().Length } | Measure-Object -Minimum).Minimum
            $body = @($block.Lines | ForEach-Object { if ($_.Length -ge $indent) { $_.Substring($indent) } else { '' } })
            return $(if ($block.Head[0] -eq '|') { ($body -join "`n").Trim() } else { ($body -join ' ').Trim() })
        }
        # A plain value may carry on over indented lines.
        & $unquote ((@($block.Head) + @($block.Lines | ForEach-Object { $_.Trim() }) | Where-Object { $_ }) -join ' ')
    }
    $list = {
        param([string] $Key)
        if (-not $blocks.Contains($Key)) { return }
        $block = $blocks[$Key]
        if ($block.Head -match '^\[(.*)\]$') {
            foreach ($item in $Matches[1] -split ',') { if ($item.Trim()) { & $unquote $item.Trim() } }
            return
        }
        foreach ($item in $block.Lines) { if ($item -match '^\s*-\s*(.+?)\s*$') { & $unquote $Matches[1] } }
    }

    $id = [string](& $scalar 'id')
    $query = [string](& $scalar 'query')
    # Files quote their description inside a block: |, then 'text'.
    $description = & $unquote ([string](& $scalar 'description'))
    # Only a path inside this repository is followed, so that no file can send the catalog elsewhere.
    $movedTo = ''
    if (-not $query -and $description -match 'https://github\.com/Azure/Azure-Sentinel/(?:blob|tree)/[^/\s]+/(\S+?\.ya?ml)') {
        $target = [uri]::UnescapeDataString($Matches[1])
        if ($target -notmatch '(^|/)\.\.(/|$)') { $movedTo = $target }
    }
    if ($id -notmatch '^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$' -or (-not $query -and -not $movedTo)) { return }

    # A data type can carry a note: "CommonSecurityLog (Fortinet)" is the table
    # CommonSecurityLog. Some files say SecurityEvents, the connector's name, for
    # the table SecurityEvent; left alone, it would read as missing data.
    $dataTypes = [System.Collections.Generic.List[string]]::new()
    if ($blocks.Contains('requiredDataConnectors')) {
        $inTypes = $false
        foreach ($line in $blocks['requiredDataConnectors'].Lines) {
            if ($line -match '^\s*(?:-\s*)?dataTypes:\s*(.*)$') {
                $inline = $Matches[1].Trim()
                $inTypes = -not $inline
                if ($inline -match '^\[(.*)\]$') { foreach ($item in $Matches[1] -split ',') { if ($item.Trim()) { $dataTypes.Add((& $unquote $item.Trim())) } } }
            }
            elseif ($line -match '^\s*-?\s*connectorId:') { $inTypes = $false }
            elseif ($inTypes -and $line -match '^\s*-\s*(.+?)\s*$') { $dataTypes.Add((& $unquote $Matches[1])) }
        }
    }
    @{
        Id          = $id.ToLowerInvariant()
        Name        = [string](& $scalar 'name')
        Description = $description
        Tactics     = @(& $list 'tactics')
        Techniques  = @(& $list 'relevantTechniques')
        DataTypes   = @($dataTypes | ForEach-Object { ($_.Trim() -split '[\s(]')[0] -replace '^SecurityEvents$', 'SecurityEvent' } | Where-Object { $_ } | Select-Object -Unique)
        Query       = $query
        Version     = [string](& $scalar 'version')
        MovedTo     = $movedTo
    }
}
