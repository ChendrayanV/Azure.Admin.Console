function Get-AACHuntingQueryCatalog {
    <#
    .SYNOPSIS
        Reads the hunting queries of the packs asked for: from the
        Azure-Sentinel repository at one commit (or a local clone), and the
        module's own Intune queries.
    .DESCRIPTION
        The packs:
          SignIn       Hunting Queries/SigninLogs
          M365         Hunting Queries/OfficeActivity and CloudAppEvents
          EntraAudit   Hunting Queries/AuditLogs
          Intune       the module's own (Get-AACIntuneHuntingQuery)
        plus, for the first three, the queries in MultipleDataSources that
        need one of the pack's tables. Stubs are followed to where the query
        moved: every file in OfficeActivity is one.

        -Ref is pinned to a commit by default, because these queries are
        written by the community: anything merged upstream reaches a workspace
        only when the module is updated to a commit someone has looked at, or
        when -Ref asks for it. GitHub is read without a token, so its limit of
        60 listings an hour applies; a clone (-Path) has no limit.

        Returns @{ Queries (AAC.SentinelHuntingQuery); Failures (file -> why it
        couldn't be read); Ref }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [ValidateSet('SignIn', 'M365', 'EntraAudit', 'Intune')]
        [string[]] $Pack = @('SignIn', 'M365', 'EntraAudit', 'Intune'),

        [ValidatePattern('^[\w./-]+$')]
        [string] $Ref = 'a716eccc9a16f107d54ae9149713a17394dec68f',

        # A local clone of Azure-Sentinel, instead of GitHub.
        [string] $Path
    )

    $packs = [ordered]@{
        SignIn     = @{ Folders = @('SigninLogs'); Tables = @('SigninLogs', 'AADNonInteractiveUserSignInLogs') }
        M365       = @{ Folders = @('OfficeActivity', 'CloudAppEvents'); Tables = @('OfficeActivity', 'CloudAppEvents') }
        EntraAudit = @{ Folders = @('AuditLogs'); Tables = @('AuditLogs') }
    }
    $wanted = @($packs.Keys | Where-Object { $Pack -contains $_ })
    $failedFiles = [ordered]@{}
    $source = if ($Path) { "local clone $Path" } else { "Azure/Azure-Sentinel@$($Ref.Substring(0, [Math]::Min(12, $Ref.Length)))" }
    $parsed = [System.Collections.Generic.List[object]]::new()

    if ($wanted.Count) {
        $folders = @(@($wanted | ForEach-Object { $packs[$_].Folders } | ForEach-Object { $_ }) + 'MultipleDataSources')
        # GitHub wants a User-Agent, and names this module to whoever reads its logs.
        $gitHubHeader = @{ 'User-Agent' = 'Azure.Admin.Console'; Accept = 'application/vnd.github+json' }
        $rawUri = { param([string] $RepoPath) "https://raw.githubusercontent.com/Azure/Azure-Sentinel/$Ref/$((($RepoPath -split '/') | ForEach-Object { [uri]::EscapeDataString($_) }) -join '/')" }

        # Named so that nothing in Invoke-AACHttpBatch - where the callbacks
        # below run - hides them.
        $fetchFiles = {
            param([object[]] $Wanted)
            $fileTexts = @{}
            if ($Path) {
                foreach ($entry in $Wanted) {
                    $onDisk = Join-Path -Path $Path -ChildPath $entry.RepoPath
                    if (Test-Path -LiteralPath $onDisk -PathType Leaf) { $fileTexts[$entry.RepoPath] = [System.IO.File]::ReadAllText($onDisk) }
                    else { $failedFiles[$entry.RepoPath] = 'not in the clone' }
                }
                return $fileTexts
            }
            $requests = @($Wanted | ForEach-Object { @{ Key = $_.RepoPath; Uri = (& $rawUri $_.RepoPath); Anonymous = $true } })
            $failures = Invoke-AACHttpBatch -Request $requests -ThrottleLimit 8 -OnResponse { param($FileKey, [string] $FileText) $fileTexts[$FileKey] = $FileText }
            foreach ($key in @($failures.Keys)) { if ($failures[$key]) { $failedFiles[$key] = $failures[$key] } }
            $fileTexts
        }

        # --- What is in each folder ----------------------------------------------------------------------------------
        $listing = [System.Collections.Generic.List[object]]::new()
        if ($Path) {
            foreach ($folder in $folders) {
                $onDisk = Join-Path -Path (Join-Path -Path $Path -ChildPath 'Hunting Queries') -ChildPath $folder
                if (-not (Test-Path -LiteralPath $onDisk -PathType Container)) {
                    throw "Azure Admin Console couldn't find '$onDisk'. -Path should be the top folder of a clone of Azure/Azure-Sentinel."
                }
                foreach ($file in Get-ChildItem -LiteralPath $onDisk -File | Where-Object Name -Match '\.ya?ml$') { $listing.Add(@{ Folder = $folder; RepoPath = "Hunting Queries/$folder/$($file.Name)" }) }
            }
        }
        else {
            $listRequests = @($folders | ForEach-Object { @{ Key = $_; Uri = "https://api.github.com/repos/Azure/Azure-Sentinel/contents/Hunting%20Queries/$_`?ref=$([uri]::EscapeDataString($Ref))"; Anonymous = $true } })
            $listFailures = Invoke-AACHttpBatch -Request $listRequests -Header $gitHubHeader -OnResponse {
                param($FolderKey, [string] $FolderText)
                foreach ($entry in @(ConvertFrom-Json -InputObject $FolderText -AsHashtable -Depth 10)) {
                    foreach ($file in @($entry)) {
                        if ([string]$file['name'] -match '\.ya?ml$') { $listing.Add(@{ Folder = $FolderKey; RepoPath = "Hunting Queries/$FolderKey/$($file['name'])" }) }
                    }
                }
            }
            $failed = @($listFailures.Keys | Where-Object { $listFailures[$_] })
            if ($failed.Count) {
                $problem = [System.InvalidOperationException]::new("Azure Admin Console couldn't list the hunting queries on GitHub ($($failed -join ', ')): $($listFailures[$failed[0]])")
                $problem.Data['AACHint'] = 'GitHub allows 60 listings an hour without a token. Wait for the limit to reset, or clone Azure/Azure-Sentinel and pass its folder with -Path. A -Ref that does not exist fails the same way.'
                throw $problem
            }
        }

        # --- The files, then wherever the stubs among them moved to -------------------------------------------------
        $texts = & $fetchFiles @($listing)
        $moved = [System.Collections.Generic.List[object]]::new()
        foreach ($entry in $listing) {
            if (-not $texts.Contains($entry.RepoPath)) { continue }
            $item = ConvertFrom-AACHuntingQueryYaml -Text $texts[$entry.RepoPath]
            if (-not $item) { continue }
            if ($item.Query) { $parsed.Add(@{ Item = $item; Folder = $entry.Folder; RepoPath = $entry.RepoPath }) }
            else { $moved.Add(@{ Folder = $entry.Folder; RepoPath = $item.MovedTo }) }
        }
        if ($moved.Count) {
            $texts = & $fetchFiles @($moved)
            foreach ($entry in $moved) {
                if (-not $texts.Contains($entry.RepoPath)) { continue }
                $item = ConvertFrom-AACHuntingQueryYaml -Text $texts[$entry.RepoPath]
                # One hop only: a stub that points at a stub is reported, not chased.
                if ($item -and $item.Query) { $parsed.Add(@{ Item = $item; Folder = $entry.Folder; RepoPath = $entry.RepoPath }) }
                else { $failedFiles[$entry.RepoPath] = 'no query in the file a stub points to' }
            }
        }
    }

    # --- Into packs: by folder, or by the tables the query needs --------------------------------------------------
    $byId = [ordered]@{}
    $add = {
        param([hashtable] $Item, [string[]] $InPacks, [string] $From, [string] $RepoPath)
        if ($byId.Contains($Item.Id)) {
            $byId[$Item.Id].Packs = @($byId[$Item.Id].Packs + $InPacks | Select-Object -Unique)
            return
        }
        $byId[$Item.Id] = @{ Item = $Item; Packs = @($InPacks); From = $From; RepoPath = $RepoPath }
    }
    foreach ($entry in $parsed) {
        $inPacks = @($wanted | Where-Object {
                $definition = $packs[$_]
                ($definition.Folders -contains $entry.Folder) -or @($entry.Item.DataTypes | Where-Object { $definition.Tables -contains $_ }).Count
            })
        if ($inPacks.Count) { & $add $entry.Item $inPacks $source $entry.RepoPath }
    }
    if ($Pack -contains 'Intune') {
        foreach ($item in Get-AACIntuneHuntingQuery) { & $add $item @('Intune') 'Azure Admin Console' '' }
    }

    $queries = @(foreach ($entry in $byId.Values) { ConvertTo-AACHuntingQueryRow -Item $entry.Item -InPack $entry.Packs -From $entry.From -RepoPath $entry.RepoPath })
    @{ Queries = @($queries | Sort-Object -Property Pack, Name); Failures = $failedFiles; Ref = $Ref }
}
