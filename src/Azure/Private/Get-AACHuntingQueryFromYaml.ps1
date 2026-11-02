function ConvertTo-AACHuntingQueryRow {
    <#
    .SYNOPSIS
        One AAC.SentinelHuntingQuery, from what ConvertFrom-AACHuntingQueryYaml
        read.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Item,

        [string[]] $InPack = @(),

        [string] $From = '',

        [string] $RepoPath = ''
    )

    $watchlists = @([regex]::Matches($Item.Query, '_GetWatchlist\(\s*[''"]([^''"]+)[''"]') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
    [pscustomobject][ordered]@{
        PSTypeName  = 'AAC.SentinelHuntingQuery'
        Name        = $Item.Name
        Id          = $Item.Id
        Pack        = $InPack -join ', '
        Tactics     = $Item.Tactics -join ', '
        Techniques  = $Item.Techniques -join ', '
        DataTypes   = $Item.DataTypes -join ', '
        Watchlists  = $watchlists -join ', '
        Readiness   = 'Unknown'
        Ready       = $false
        Missing     = ''
        Deployment  = 'Unknown'
        Version     = $Item.Version
        Source      = $From
        RepoPath    = $RepoPath
        Description = $Item.Description
        Query       = $Item.Query
    }
}

function Get-AACHuntingQueryFromYaml {
    <#
    .SYNOPSIS
        Reads hunting queries from the YAML files someone named: links to GitHub
        or files on this computer.
    .DESCRIPTION
        -Source takes:
          https://github.com/{owner}/{repo}/blob/{branch or commit}/{path}.yaml
          https://raw.githubusercontent.com/{owner}/{repo}/{branch or commit}/{path}.yaml
          a local path, already made full by the caller
        Nothing else: a query is deployed to a security workspace, so this reads
        the sources the module can name, not any address. A file elsewhere can
        be downloaded and passed by its path.

        A stub in Azure/Azure-Sentinel is followed to where the query moved, at
        the same branch or commit. A stub anywhere else can't be, and is
        reported.

        The caller named these files, so one that can't be read stops
        everything: deploying only some of them could go unnoticed.

        Returns @{ Queries (AAC.SentinelHuntingQuery, in the pack YAML);
        Failures (always empty); Ref (empty) }, as Get-AACHuntingQueryCatalog does.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string[]] $Source
    )

    $failed = [ordered]@{}
    $targets = @(foreach ($entry in $Source) {
            $link = $entry -replace '[?#].*$', ''
            if ($entry -match '^[a-zA-Z][a-zA-Z0-9+.-]*://') {
                $parts = if ($link -match '^https://github\.com/([^/]+)/([^/]+)/blob/([^/]+)/(.+)$' -or $link -match '^https://raw\.githubusercontent\.com/([^/]+)/([^/]+)/(?:refs/(?:heads|tags)/)?([^/]+)/(.+)$') { @($Matches[1], $Matches[2], $Matches[3], $Matches[4]) }
                if (-not $parts -or $parts[3] -notmatch '\.ya?ml$') {
                    $failed[$entry] = 'not a link to a YAML file on GitHub. Use a github.com/{owner}/{repo}/blob/... or raw.githubusercontent.com link, or download the file and pass its path.'
                    continue
                }
                $repo = "$($parts[0])/$($parts[1])"
                @{ Source = $entry; Uri = "https://raw.githubusercontent.com/$repo/$($parts[2])/$($parts[3])"; Repo = $repo; Branch = $parts[2]; From = "$repo@$($parts[2])"; RepoPath = [uri]::UnescapeDataString($parts[3]) }
            }
            else {
                @{ Source = $entry; Uri = ''; Repo = ''; Branch = ''; From = 'local file'; RepoPath = (Split-Path -Path $entry -Leaf) }
            }
        })

    # Named so that nothing in Invoke-AACHttpBatch - where the callback runs - hides it.
    $fetchTexts = {
        param([object[]] $Wanted)
        $yamlTexts = @{}
        foreach ($target in @($Wanted | Where-Object { -not $_.Uri })) {
            if (Test-Path -LiteralPath $target.Source -PathType Leaf) { $yamlTexts[$target.Source] = [System.IO.File]::ReadAllText($target.Source) }
            else { $failed[$target.Source] = 'no such file' }
        }
        $requests = @($Wanted | Where-Object { $_.Uri } | ForEach-Object { @{ Key = $_.Source; Uri = $_.Uri; Anonymous = $true } })
        if ($requests.Count) {
            $failures = Invoke-AACHttpBatch -Request $requests -ThrottleLimit 8 -OnResponse { param($YamlKey, [string] $YamlText) $yamlTexts[$YamlKey] = $YamlText }
            foreach ($key in @($failures.Keys)) { if ($failures[$key]) { $failed[$key] = $failures[$key] } }
        }
        $yamlTexts
    }

    $rows = [ordered]@{}
    $addRow = {
        param([hashtable] $Item, [hashtable] $Target)
        if (-not $rows.Contains($Item.Id)) { $rows[$Item.Id] = ConvertTo-AACHuntingQueryRow -Item $Item -InPack @('YAML') -From $Target.From -RepoPath $Target.RepoPath }
    }
    $unreadable = 'no query in it, or its id is not a GUID: a hunting query needs both.'
    $texts = & $fetchTexts $targets
    $moved = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($target in $targets) {
        if (-not $texts.Contains($target.Source)) { continue }
        $item = ConvertFrom-AACHuntingQueryYaml -Text $texts[$target.Source]
        if (-not $item) { $failed[$target.Source] = $unreadable }
        elseif ($item.Query) { & $addRow $item $target }
        elseif ($target.Repo -eq 'Azure/Azure-Sentinel') {
            $moved.Add(@{ Source = $target.Source; Uri = "https://raw.githubusercontent.com/$($target.Repo)/$($target.Branch)/$((($item.MovedTo -split '/') | ForEach-Object { [uri]::EscapeDataString($_) }) -join '/')"; From = $target.From; RepoPath = $item.MovedTo })
        }
        else { $failed[$target.Source] = "this file only says the query moved to $($item.MovedTo). Pass that file instead." }
    }
    if ($moved.Count) {
        $texts = & $fetchTexts @($moved)
        foreach ($target in $moved) {
            if (-not $texts.Contains($target.Source)) { continue }
            $item = ConvertFrom-AACHuntingQueryYaml -Text $texts[$target.Source]
            # One hop only, as in the catalog.
            if ($item -and $item.Query) { & $addRow $item $target }
            else { $failed[$target.Source] = "this file says the query moved to $($target.RepoPath), and there is no query there." }
        }
    }
    if ($failed.Count) {
        $problem = [System.InvalidOperationException]::new("Azure Admin Console couldn't read $($failed.Count) YAML source(s), so nothing was done: $(@($failed.Keys | ForEach-Object { "$_ - $($failed[$_])" }) -join ' | ')")
        $problem.Data['AACHint'] = 'Check the link or path. This reads GitHub without a token, so a private repository looks like a missing file: download the file and pass its path.'
        throw $problem
    }
    @{ Queries = @($rows.Values); Failures = [ordered]@{}; Ref = '' }
}
