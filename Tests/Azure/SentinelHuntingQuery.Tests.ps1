<#
    Unit tests for Find-, Get- and Deploy-AACSentinelHuntingQuery over made-up
    files and a made-up workspace (Fixtures\ContosoHunting.ps1). GitHub is faked
    at the HTTP send, so the batch and the catalog run for real; Resource
    Manager, Resource Graph, KQL and the writes are faked; the rest runs for real.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
}

BeforeAll {
    $script:contoso = & (Join-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -ChildPath 'Fixtures/ContosoHunting.ps1')
    $script:capture = {
        param([scriptblock] $Render)
        $real = [Spectre.Console.AnsiConsole]::Console
        $buffer = [System.IO.StringWriter]::new()
        $settings = [Spectre.Console.AnsiConsoleSettings]::new()
        $settings.Out = [Spectre.Console.AnsiConsoleOutput]::new($buffer)
        $settings.Ansi = [Spectre.Console.AnsiSupport]::No
        $settings.Enrichment.UseDefaultEnrichers = $false
        $console = [Spectre.Console.AnsiConsole]::Create($settings)
        $console.Profile.Width = 220
        try { [Spectre.Console.AnsiConsole]::Console = $console; $output = @(& $Render) }
        finally { [Spectre.Console.AnsiConsole]::Console = $real }
        [pscustomobject]@{ Text = $buffer.ToString(); Output = $output }
    }
    $script:hash = { param([string] $Query) InModuleScope 'Azure.Admin.Console' -Parameters @{ Q = $Query } { param($Q) Get-AACHuntingQueryHash -Query $Q } }
    # A saved search as Azure returns it.
    $script:savedSearch = {
        param([string] $Id, [string] $Name, [string] $Query, [hashtable] $Tag = @{})
        $tags = @(foreach ($key in $Tag.Keys) { @{ name = $key; value = $Tag[$key] } })
        @{ id = "$($script:contoso.ResourceId)/savedSearches/$Id"; name = $Id; etag = 'W/"etag-1"'; properties = @{ category = 'Hunting Queries'; displayName = $Name; query = $Query; version = 2; tags = $tags } }
    }
    $script:mockAzure = {
        $script:gitHubUris = [System.Collections.Generic.List[string]]::new()
        $script:gitHubStatus = 200
        $script:saved = @()
        $script:onboarding = @{ Status = 200; Error = ''; Body = $null; Items = @(@{ name = 'default' }) }
        $script:watchlists = @{ Status = 200; Error = ''; Body = $null; Items = @() }
        $script:savedError = $null
        $script:tablesError = $null
        $script:writes = [System.Collections.Generic.List[object]]::new()
        $script:writeFails = ''
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Send-AACHttpRequest -MockWith {
            $script:gitHubUris.Add($Uri)
            $text = ''
            $code = 200
            if ($Uri -match '/contents/Hunting%20Queries/(\w+)') {
                $folder = $Matches[1]
                $code = $script:gitHubStatus
                $text = if ($code -eq 200) { ConvertTo-Json -InputObject @($script:contoso.Listing[$folder] | ForEach-Object { @{ name = $_; type = 'file' } }) -Compress } else { '{"message":"API rate limit exceeded"}' }
            }
            elseif ($Uri -match 'raw\.githubusercontent\.com/[^/]+/[^/]+/[^/]+/(.+)$') {
                $repoPath = [uri]::UnescapeDataString($Matches[1])
                if ($script:contoso.Files.ContainsKey($repoPath)) { $text = $script:contoso.Files[$repoPath] } else { $code = 404; $text = '404: Not Found' }
            }
            else { $code = 500; $text = "unexpected $Uri" }
            $response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]$code)
            $response.Content = [System.Net.Http.StringContent]::new($text)
            [System.Threading.Tasks.Task]::FromResult($response)
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith { @{ Rows = @{ workspace = @(@{ id = $script:contoso.ResourceId }) }; Errors = @{} } }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -MockWith {
            $out = @{}
            foreach ($u in $Uri) {
                $out[$u] = switch -Regex ($u) {
                    '/workspaces/law-contoso-sentinel\?' { @{ Status = 200; Body = $script:contoso.Workspace; Items = $null; Error = '' } }
                    '/savedSearches\?' { if ($script:savedError) { @{ Status = 403; Error = $script:savedError; Body = $null; Items = $null } } else { @{ Status = 200; Error = ''; Body = $null; Items = @($script:saved) } } }
                    '/onboardingStates\?' { $script:onboarding }
                    '/watchlists\?' { $script:watchlists }
                }
            }
            $out
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACLogQueryBatch -MockWith {
            if ($script:tablesError) { return @{ Rows = @{ tables = @() }; Errors = @{ tables = $script:tablesError } } }
            @{ Rows = @{ tables = @($script:contoso.Tables | ForEach-Object { [ordered]@{ DataType = $_ } }) }; Errors = @{} }
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmWrite -MockWith {
            if ($script:writeFails -and $Body.properties.displayName -eq $script:writeFails) { throw 'Forbidden' }
            $script:writes.Add(@{ Method = $Method; Uri = $Uri; Body = $Body })
            @{}
        }
    }
    $script:written = { param([string] $Id) @($script:writes | Where-Object { $_.Uri -like "*/savedSearches/$Id`?*" })[0] }
}

Describe 'Azure Admin Console - reading a hunting query file' {
    It 'reads the keys a query needs, and leaves out what it doesn''t' {
        $text = $script:contoso.Files['Hunting Queries/SigninLogs/BruteForce.yaml']
        $item = InModuleScope 'Azure.Admin.Console' -Parameters @{ T = $text } { param($T) ConvertFrom-AACHuntingQueryYaml -Text $T }
        $item.Id | Should -Be $script:contoso.Id.BruteForce -Because 'IDs are compared in lower case'
        $item.Name | Should -Be 'Brute force on sign-ins'
        $item.Description | Should -Be "Many failed sign-ins`nfollowed by a success." -Because 'the quotes around a block are the file''s, not the text''s'
        @($item.Tactics) | Should -Be @('CredentialAccess', 'InitialAccess')
        @($item.Techniques) | Should -Be @('T1110')
        @($item.DataTypes) | Should -Be @('SigninLogs')
        $item.Version | Should -Be '1.2.0'
        $item.Query | Should -Be "let starttime = todatetime('{{StartTimeISO}}');`n`nSigninLogs`n  | where ResultType != 0" -Because 'blank lines and inner indents are kept, and placeholders are left for the Hunting page'
    }

    It 'reads inline lists and Windows line endings, and drops a data type''s note' {
        $inline = InModuleScope 'Azure.Admin.Console' -Parameters @{ T = $script:contoso.Files['Solutions/Cloud Identity/Hunting Queries/Disabled.yaml'] } { param($T) ConvertFrom-AACHuntingQueryYaml -Text $T }
        @($inline.Tactics) | Should -Be @('InitialAccess')
        @($inline.DataTypes) | Should -Be @('AADNonInteractiveUserSignInLogs')
        $crlf = InModuleScope 'Azure.Admin.Console' -Parameters @{ T = $script:contoso.Files['Solutions/Microsoft 365/Hunting Queries/Mail.yaml'] } { param($T) ConvertFrom-AACHuntingQueryYaml -Text $T }
        @($crlf.DataTypes) | Should -Be @('OfficeActivity')
        $crlf.Query | Should -Be "OfficeActivity`n| where Operation == 'New-TransportRule'"
    }

    It 'calls the connector name SecurityEvents by its table''s name' {
        $text = "id: aaaaaaaa-0000-4000-8000-00000000000a`nname: n`ndescription: d`nrequiredDataConnectors:`n  - connectorId: SecurityEvents`n    dataTypes:`n      - SecurityEvents`nquery: |`n  SecurityEvent`n"
        @((InModuleScope 'Azure.Admin.Console' -Parameters @{ T = $text } { param($T) ConvertFrom-AACHuntingQueryYaml -Text $T }).DataTypes) | Should -Be @('SecurityEvent')
    }

    It 'says where a stub moved to, decoded' {
        $item = InModuleScope 'Azure.Admin.Console' -Parameters @{ T = $script:contoso.Files['Hunting Queries/OfficeActivity/Mail.yaml'] } { param($T) ConvertFrom-AACHuntingQueryYaml -Text $T }
        $item.MovedTo | Should -Be 'Solutions/Microsoft 365/Hunting Queries/Mail.yaml'
        $item.Query | Should -Be ''
    }

    It 'returns nothing for <Title>' -ForEach @(
        @{ Title = 'a file with no id'; Text = "name: n`nquery: |`n  T`n" }
        @{ Title = 'an id that is not a GUID, as it becomes part of an Azure path'; Text = "id: ../../other/x`nname: n`nquery: |`n  T`n" }
        @{ Title = 'a stub pointing to another repository'; Text = "id: aaaaaaaa-0000-4000-8000-00000000000a`ndescription: moved to https://github.com/someone/other/blob/master/Evil.yaml`n" }
        @{ Title = 'a stub climbing out of this one'; Text = "id: aaaaaaaa-0000-4000-8000-00000000000a`ndescription: moved to https://github.com/Azure/Azure-Sentinel/blob/master/../../other/Evil.yaml`n" }
        @{ Title = 'an empty file'; Text = '' }
    ) {
        InModuleScope 'Azure.Admin.Console' -Parameters @{ T = $Text } { param($T) ConvertFrom-AACHuntingQueryYaml -Text $T } | Should -BeNullOrEmpty
    }
}

Describe 'Azure Admin Console - the hunting query catalog' {
    BeforeEach { & $script:mockAzure }

    It 'follows stubs, and puts queries in packs by folder and by the tables they need' {
        $catalog = InModuleScope 'Azure.Admin.Console' { Get-AACHuntingQueryCatalog -Pack SignIn, M365 }
        $byName = @{}; foreach ($q in $catalog.Queries) { $byName[$q.Name] = $q }
        $byName['Mail redirect rule'].Pack | Should -Be 'M365' -Because 'the real query is where the stub says'
        $byName['Mail redirect rule'].RepoPath | Should -Be 'Solutions/Microsoft 365/Hunting Queries/Mail.yaml'
        $byName['Sign-ins to disabled accounts'].Pack | Should -Be 'SignIn'
        $byName['Sign-in then mailbox access'].Pack | Should -Be 'SignIn, M365' -Because 'it needs a table of each'
        $byName.Contains('Consent granted to a VIP') | Should -BeFalse -Because 'EntraAudit wasn''t asked for'
        $byName.Contains('AWS only') | Should -BeFalse -Because 'no pack needs its table'
        $byName.Contains('Mail rule (stub)') | Should -BeFalse
    }

    It 'never fetches what a stub points to outside the repository, and skips non-YAML files' {
        $null = InModuleScope 'Azure.Admin.Console' { Get-AACHuntingQueryCatalog -Pack SignIn }
        @($script:gitHubUris | Where-Object { $_ -match 'Evil|someone|readme' }).Count | Should -Be 0
    }

    It 'reads GitHub at the pinned commit by default, and at -Ref when asked' {
        $null = InModuleScope 'Azure.Admin.Console' { Get-AACHuntingQueryCatalog -Pack SignIn }
        @($script:gitHubUris | Where-Object { $_ -match 'master' }).Count | Should -Be 0 -Because 'upstream changes must not reach a workspace unasked'
        @($script:gitHubUris | Where-Object { $_ -match 'a716eccc9a16f107d54ae9149713a17394dec68f' }).Count | Should -Be $script:gitHubUris.Count
        $script:gitHubUris.Clear()
        $null = InModuleScope 'Azure.Admin.Console' { Get-AACHuntingQueryCatalog -Pack SignIn -Ref 'master' }
        @($script:gitHubUris | Where-Object { $_ -match 'master' }).Count | Should -Be $script:gitHubUris.Count
    }

    It 'has the Intune pack without touching GitHub' {
        $catalog = InModuleScope 'Azure.Admin.Console' { Get-AACHuntingQueryCatalog -Pack Intune }
        $script:gitHubUris.Count | Should -Be 0
        @($catalog.Queries).Count | Should -Be 4
        @($catalog.Queries.Source | Select-Object -Unique) | Should -Be @('Azure Admin Console')
        @($catalog.Queries | Where-Object { $_.Id -notmatch '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$' }).Count | Should -Be 0
        @($catalog.Queries.DataTypes | Select-Object -Unique | Sort-Object) | Should -Be @('IntuneAuditLogs', 'IntuneDevices', 'IntuneOperationalLogs')
    }

    It 'reads the watchlists a query uses' {
        $catalog = InModuleScope 'Azure.Admin.Console' { Get-AACHuntingQueryCatalog -Pack EntraAudit }
        @($catalog.Queries | Where-Object Name -EQ 'Consent granted to a VIP')[0].Watchlists | Should -Be 'VIPUsers'
    }

    It 'says what to do when GitHub refuses' {
        $script:gitHubStatus = 403
        { InModuleScope 'Azure.Admin.Console' { Get-AACHuntingQueryCatalog -Pack SignIn } } | Should -Throw -ExpectedMessage "*couldn't list the hunting queries on GitHub*"
    }

    It 'reports a file it couldn''t read, and carries on' {
        $script:contoso.Listing.SigninLogs += 'Gone.yaml'
        try {
            $catalog = InModuleScope 'Azure.Admin.Console' { Get-AACHuntingQueryCatalog -Pack SignIn }
            $catalog.Failures.Contains('Hunting Queries/SigninLogs/Gone.yaml') | Should -BeTrue
            @($catalog.Queries).Count | Should -BeGreaterThan 0
        }
        finally { $script:contoso.Listing.SigninLogs = @($script:contoso.Listing.SigninLogs | Where-Object { $_ -ne 'Gone.yaml' }) }
    }

    It 'reads a local clone instead of GitHub' {
        foreach ($repoPath in $script:contoso.Files.Keys) {
            $file = Join-Path $TestDrive $repoPath
            $null = New-Item -ItemType Directory -Path (Split-Path -Path $file -Parent) -Force
            [System.IO.File]::WriteAllText($file, $script:contoso.Files[$repoPath])
        }
        $catalog = InModuleScope 'Azure.Admin.Console' -Parameters @{ Clone = [string]$TestDrive } { param($Clone) Get-AACHuntingQueryCatalog -Pack M365 -Path $Clone }
        $script:gitHubUris.Count | Should -Be 0
        $catalog.Queries.Name | Should -Contain 'Mail redirect rule'
    }

    It 'says what -Path should be when it isn''t a clone' {
        { InModuleScope 'Azure.Admin.Console' -Parameters @{ Clone = [string]$TestDrive } { param($Clone) Get-AACHuntingQueryCatalog -Pack EntraAudit -Path (Join-Path $Clone 'nowhere') } } | Should -Throw -ExpectedMessage '*top folder of a clone*'
    }
}

Describe 'Azure Admin Console - -YamlSource' {
    BeforeEach { & $script:mockAzure }

    It 'turns a <Title> link into the raw file''s address' -ForEach @(
        @{ Title = 'github.com blob'; Link = 'https://github.com/contoso/queries/blob/main/custom/Own.yaml' }
        @{ Title = 'raw'; Link = 'https://raw.githubusercontent.com/contoso/queries/main/custom/Own.yaml' }
        @{ Title = 'raw refs/heads'; Link = 'https://raw.githubusercontent.com/contoso/queries/refs/heads/main/custom/Own.yaml' }
        @{ Title = 'github.com blob with a query string'; Link = 'https://github.com/contoso/queries/blob/main/custom/Own.yaml?plain=1#L3' }
    ) {
        $rows = @(Find-AACSentinelHuntingQuery -YamlSource $Link -NoDisplay)
        @($script:gitHubUris) | Should -Be @('https://raw.githubusercontent.com/contoso/queries/main/custom/Own.yaml')
        $rows.Name | Should -Be 'Our own query'
        $rows.Pack | Should -Be 'YAML'
        $rows.Source | Should -Be 'contoso/queries@main'
        $rows.RepoPath | Should -Be 'custom/Own.yaml'
    }

    It 'follows a stub in Azure-Sentinel to where the query moved, at the same branch' {
        $row = Find-AACSentinelHuntingQuery -YamlSource 'https://github.com/Azure/Azure-Sentinel/blob/my-branch/Hunting%20Queries/OfficeActivity/Mail.yaml' -NoDisplay
        $row.Name | Should -Be 'Mail redirect rule'
        $row.Id | Should -Be $script:contoso.Id.Mail
        $row.RepoPath | Should -Be 'Solutions/Microsoft 365/Hunting Queries/Mail.yaml'
        $script:gitHubUris | Should -Contain 'https://raw.githubusercontent.com/Azure/Azure-Sentinel/my-branch/Solutions/Microsoft%20365/Hunting%20Queries/Mail.yaml'
    }

    It 'reads a local file' {
        $file = Join-Path $TestDrive 'own.yaml'
        [System.IO.File]::WriteAllText($file, $script:contoso.Files['custom/Own.yaml'])
        $row = Find-AACSentinelHuntingQuery -YamlSource $file -NoDisplay
        $row.Name | Should -Be 'Our own query'
        $row.Source | Should -Be 'local file'
        $script:gitHubUris.Count | Should -Be 0
    }

    It 'refuses <Title>, and fetches nothing' -ForEach @(
        @{ Title = 'plain http'; Link = 'http://github.com/contoso/queries/blob/main/custom/Own.yaml' }
        @{ Title = 'another site'; Link = 'https://evil.example/custom/Own.yaml' }
        @{ Title = 'a site posing as GitHub'; Link = 'https://github.com.evil.example/contoso/queries/blob/main/custom/Own.yaml' }
        @{ Title = 'a GitHub folder'; Link = 'https://github.com/contoso/queries/tree/main/custom' }
        @{ Title = 'a file that isn''t YAML'; Link = 'https://github.com/contoso/queries/blob/main/custom/Own.txt' }
    ) {
        { $null = & $script:capture { Find-AACSentinelHuntingQuery -YamlSource $Link -NoDisplay } } | Should -Throw -ExpectedMessage '*not a link to a YAML file on GitHub*'
        $script:gitHubUris.Count | Should -Be 0
    }

    It 'stops, deploying nothing, when one of several files can''t be used: <Title>' -ForEach @(
        @{ Title = 'it doesn''t exist'; Bad = 'https://github.com/contoso/queries/blob/main/custom/Gone.yaml'; Why = '*Gone.yaml*' }
        @{ Title = 'its id could reach another resource'; Bad = 'https://github.com/contoso/queries/blob/main/custom/BadId.yaml'; Why = '*its id is not a GUID*' }
        @{ Title = 'a stub outside Azure-Sentinel'; Bad = 'https://github.com/contoso/queries/blob/main/custom/StubElsewhere.yaml'; Why = '*only says the query moved*' }
        @{ Title = 'no such local file'; Bad = 'nowhere/missing.yaml'; Why = '*no such file*' }
    ) {
        $good = 'https://github.com/contoso/queries/blob/main/custom/Own.yaml'
        { $null = & $script:capture { Deploy-AACSentinelHuntingQuery -WorkspaceId $script:contoso.ResourceId -YamlSource $good, $Bad -Force -NoDisplay } } | Should -Throw -ExpectedMessage $Why
        $script:writes.Count | Should -Be 0
    }

    It 'deploys a file, tagged with where it came from' {
        $result = Deploy-AACSentinelHuntingQuery -WorkspaceId $script:contoso.ResourceId -YamlSource 'https://github.com/contoso/queries/blob/main/custom/Own.yaml' -Force -NoDisplay
        $result.Created | Should -Be 1
        $write = & $script:written 'aaaaaaaa-0000-4000-8000-000000000010'
        $write.Body.properties.displayName | Should -Be 'Our own query'
        @($write.Body.properties.tags | Where-Object name -EQ 'aacSource')[0].value | Should -Be 'contoso/queries@main/custom/Own.yaml'
    }

    It 'deploys the same query once when two links reach it' {
        $link = 'https://github.com/Azure/Azure-Sentinel/blob/master/Hunting%20Queries/OfficeActivity/Mail.yaml'
        $direct = 'https://github.com/Azure/Azure-Sentinel/blob/master/Solutions/Microsoft%20365/Hunting%20Queries/Mail.yaml'
        (Deploy-AACSentinelHuntingQuery -WorkspaceId $script:contoso.ResourceId -YamlSource $link, $direct -Force -NoDisplay).Created | Should -Be 1
    }

    It 'holds a file to the same rules as a pack: not ready is skipped, unless asked' {
        $link = 'https://github.com/contoso/queries/blob/main/custom/Own.yaml'
        $script:contoso.Tables = @($script:contoso.Tables | Where-Object { $_ -ne 'SigninLogs' })
        try {
            $result = Deploy-AACSentinelHuntingQuery -WorkspaceId $script:contoso.ResourceId -YamlSource $link -Force -NoDisplay
            $result.Status | Should -Be 'NoChanges'
            @($result.Queries)[0].Reason | Should -Match 'Missing data: SigninLogs'
            (Deploy-AACSentinelHuntingQuery -WorkspaceId $script:contoso.ResourceId -YamlSource $link -IncludeNotReady -Force -NoDisplay).Created | Should -Be 1
        }
        finally { $script:contoso.Tables = @($script:contoso.Tables) + 'SigninLogs' }
    }

    It 'takes the workspace as -WorkspaceName with -ResourceGroupName, as a script might' {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Resolve-AACLogResource -MockWith { @{ Id = $script:contoso.ResourceId } }
        $null = Deploy-AACSentinelHuntingQuery -SubscriptionId '11111111-1111-1111-1111-111111111111' -ResourceGroupName 'rg-contoso-sec' -WorkspaceName 'law-contoso-sentinel' -YamlSource 'https://github.com/contoso/queries/blob/main/custom/Own.yaml' -WhatIf -NoDisplay
        Should -Invoke -ModuleName 'Azure.Admin.Console' Resolve-AACLogResource -ParameterFilter { $Name -eq 'law-contoso-sentinel' -and $ResourceGroupName -eq 'rg-contoso-sec' -and $SubscriptionId -contains '11111111-1111-1111-1111-111111111111' }
    }

    It 'says so when -Name matches none of the files' {
        (& $script:capture { Find-AACSentinelHuntingQuery -YamlSource 'https://github.com/contoso/queries/blob/main/custom/Own.yaml' -Name 'nothing like it' -NoPaging }).Text | Should -Match 'No hunting query matches'
    }

    It 'shows the source in the view' {
        $text = (& $script:capture { Find-AACSentinelHuntingQuery -YamlSource 'https://github.com/contoso/queries/blob/main/custom/Own.yaml' -NoPaging }).Text
        foreach ($expected in 'YAML pack', 'Our own query', 'contoso/queries@main') { $text | Should -Match ([regex]::Escape($expected)) }
    }
}

Describe 'Azure Admin Console - Find-AACSentinelHuntingQuery' {
    BeforeEach { & $script:mockAzure }

    It 'lists the catalog with no workspace and no Azure sign-in' {
        $rows = @(Find-AACSentinelHuntingQuery -Pack Intune -NoDisplay)
        $rows.Count | Should -Be 4
        $rows[0].PSObject.TypeNames[0] | Should -Be 'AAC.SentinelHuntingQuery'
        @($rows.Readiness | Select-Object -Unique) | Should -Be @('Unknown')
        Should -Invoke -ModuleName 'Azure.Admin.Console' Get-AACAccessToken -Exactly 0
    }

    It 'says what a workspace is ready for: <Name>' -ForEach @(
        @{ Name = 'Brute force on sign-ins'; Readiness = 'Ready'; Missing = '' }
        @{ Name = 'Cloud app policy change'; Readiness = 'Missing data'; Missing = 'CloudAppEvents' }
        @{ Name = 'Consent granted to a VIP'; Readiness = 'Missing watchlist'; Missing = 'watchlist VIPUsers' }
    ) {
        $row = @(Find-AACSentinelHuntingQuery -WorkspaceId $script:contoso.ResourceId -NoDisplay | Where-Object Name -EQ $Name)[0]
        $row.Readiness | Should -Be $Readiness
        $row.Missing | Should -Be $Missing
        $row.Ready | Should -Be ($Readiness -eq 'Ready')
        $row.Deployment | Should -Be 'New'
    }

    It 'treats a watchlist that exists as there, whatever its case' {
        $script:watchlists = @{ Status = 200; Error = ''; Body = $null; Items = @(@{ properties = @{ watchlistAlias = 'vipusers' } }) }
        @(Find-AACSentinelHuntingQuery -Pack EntraAudit -WorkspaceId $script:contoso.ResourceId -NoDisplay | Where-Object Name -EQ 'Consent granted to a VIP')[0].Ready | Should -BeTrue
    }

    It 'says Unknown, not Missing, when the tables couldn''t be read, and reports why' {
        $script:tablesError = 'Query timed out'
        $result = & $script:capture { Find-AACSentinelHuntingQuery -Pack SignIn -WorkspaceId $script:contoso.ResourceId -NoPaging -PassThru }
        @($result.Output.Readiness | Select-Object -Unique) | Should -Be @('Unknown')
        @($result.Output | Where-Object Ready).Count | Should -Be 0
        $result.Text | Should -Match 'Query timed out'
    }

    It 'gives each query its deployment state: <Title>' -ForEach @(
        @{ Title = 'Current: the same query, whatever the line endings'; Expected = 'Current'; Saved = { & $script:savedSearch $script:contoso.Id.Mail 'Mail redirect rule' "OfficeActivity`r`n| where Operation == 'New-TransportRule'`r`n" } }
        @{ Title = 'Update available: unedited since this module deployed it'; Expected = 'Update available'; Saved = { & $script:savedSearch $script:contoso.Id.Mail 'Mail redirect rule' 'old query' @{ aacQueryHash = (& $script:hash 'old query') } } }
        @{ Title = 'Changed: edited since'; Expected = 'Changed'; Saved = { & $script:savedSearch $script:contoso.Id.Mail 'Mail redirect rule' 'edited' @{ aacQueryHash = (& $script:hash 'old query') } } }
        @{ Title = 'Changed: not deployed by this module'; Expected = 'Changed'; Saved = { & $script:savedSearch $script:contoso.Id.Mail 'Mail redirect rule' 'someone else''s' } }
        @{ Title = 'Other copy: this name under another ID'; Expected = 'Other copy'; Saved = { & $script:savedSearch 'Microsoft_365_Hunting_Query_1' 'MAIL REDIRECT RULE' 'from Content hub' } }
    ) {
        $script:saved = @(& $Saved)
        @(Find-AACSentinelHuntingQuery -Pack M365 -WorkspaceId $script:contoso.ResourceId -NoDisplay | Where-Object Name -EQ 'Mail redirect rule')[0].Deployment | Should -Be $Expected
    }

    It 'filters by name and tactic' {
        @(Find-AACSentinelHuntingQuery -Pack SignIn -Name '*disabled*' -NoDisplay).Name | Should -Be 'Sign-ins to disabled accounts'
        @(Find-AACSentinelHuntingQuery -Pack SignIn -Tactic CredentialAccess -NoDisplay).Name | Should -Be 'Brute force on sign-ins'
    }

    It 'warns when Sentinel isn''t enabled, and doesn''t query the workspace' {
        $script:onboarding = @{ Status = 200; Error = ''; Body = $null; Items = @() }
        $text = (& $script:capture { Find-AACSentinelHuntingQuery -Pack Intune -WorkspaceId $script:contoso.ResourceId -NoPaging }).Text
        $text | Should -Match 'Microsoft Sentinel is not enabled'
        Should -Invoke -ModuleName 'Azure.Admin.Console' Invoke-AACLogQueryBatch -Exactly 0
    }

    It 'shows the queries, with readiness once there is a workspace' {
        $text = (& $script:capture { Find-AACSentinelHuntingQuery -Pack SignIn, Intune -WorkspaceId $script:contoso.ResourceId -NoPaging }).Text
        foreach ($expected in 'Hunting queries', 'Brute force on sign-ins', 'Intune - burst of device wipes', 'Ready', 'Missing data', 'New') { $text | Should -Match ([regex]::Escape($expected)) }
    }

    It 'writes the reports instead of the view' {
        $csv = Join-Path $TestDrive 'q.csv'
        $html = Join-Path $TestDrive 'q.html'
        $text = (& $script:capture { Find-AACSentinelHuntingQuery -Pack Intune -CsvPath $csv -HtmlPath $html }).Text
        $text | Should -Not -Match 'burst of device wipes'
        @(Import-Csv -LiteralPath $csv).Count | Should -Be 4
        (Get-Content -LiteralPath $html -Raw) | Should -Match 'burst of device wipes'
    }

    It 'writes a PDF report' -Skip:(-not ($IsWindows -and $PSVersionTable.PSVersion -ge [version]'7.4')) {
        $pdf = Join-Path $TestDrive 'q.pdf'
        $null = & $script:capture { Find-AACSentinelHuntingQuery -Pack Intune -PdfPath $pdf }
        [System.Text.Encoding]::ASCII.GetString([System.IO.File]::ReadAllBytes($pdf), 0, 5) | Should -Be '%PDF-'
    }
}

Describe 'Azure Admin Console - Get-AACSentinelHuntingQuery' {
    BeforeEach { & $script:mockAzure }

    It 'lists only hunting queries, and tells this module''s from the rest' {
        $mine = & $script:savedSearch 'id-mine' 'Mine' 'T | take 1' @{ tactics = 'Impact,Execution'; techniques = 'T1485'; description = 'd'; aacQueryHash = (& $script:hash 'T | take 1'); aacSource = 'Azure Admin Console'; aacVersion = '1.0.0' }
        $edited = & $script:savedSearch 'id-edited' 'Edited' 'edited' @{ aacQueryHash = (& $script:hash 'original') }
        $other = & $script:savedSearch 'id-other' 'Other' 'T'
        $notHunting = & $script:savedSearch 'id-log' 'A log search' 'T'
        $notHunting.properties.category = 'Log Management'
        $script:saved = @($mine, $edited, $other, $notHunting)
        $rows = @(Get-AACSentinelHuntingQuery -WorkspaceId $script:contoso.ResourceId -NoDisplay)
        $rows[0].PSObject.TypeNames[0] | Should -Be 'AAC.SentinelInstalledHuntingQuery'
        @($rows.Name) | Should -Be @('Edited', 'Mine', 'Other')
        $byName = @{}; foreach ($r in $rows) { $byName[$r.Name] = $r }
        $byName['Mine'].Source | Should -Be 'This module'
        $byName['Mine'].Edited | Should -BeFalse
        $byName['Mine'].Tactics | Should -Be 'Impact, Execution'
        $byName['Mine'].Techniques | Should -Be 'T1485'
        $byName['Mine'].Version | Should -Be '1.0.0'
        $byName['Edited'].Edited | Should -BeTrue
        $byName['Other'].Source | Should -Be 'Elsewhere'
        $byName['Other'].Edited | Should -BeNullOrEmpty -Because 'this module can''t judge what it didn''t deploy'
    }

    It 'reads only the workspace and its saved searches' {
        $null = Get-AACSentinelHuntingQuery -WorkspaceId $script:contoso.ResourceId -NoDisplay
        Should -Invoke -ModuleName 'Azure.Admin.Console' Invoke-AACLogQueryBatch -Exactly 0
        Should -Invoke -ModuleName 'Azure.Admin.Console' Send-AACHttpRequest -Exactly 0 -Because 'it never reads GitHub'
    }

    It 'filters by name and tactic' {
        $script:saved = @((& $script:savedSearch 'a' 'Alpha' 'T' @{ tactics = 'Impact' }), (& $script:savedSearch 'b' 'Beta' 'T' @{ tactics = 'Discovery' }))
        @(Get-AACSentinelHuntingQuery -WorkspaceId $script:contoso.ResourceId -Name 'Al*' -NoDisplay).Name | Should -Be 'Alpha'
        @(Get-AACSentinelHuntingQuery -WorkspaceId $script:contoso.ResourceId -Tactic Discovery -NoDisplay).Name | Should -Be 'Beta'
    }

    It 'stops, rather than saying there are none, when the list can''t be read' {
        $script:savedError = 'Forbidden'
        { $null = & $script:capture { Get-AACSentinelHuntingQuery -WorkspaceId $script:contoso.ResourceId -NoDisplay } } | Should -Throw -ExpectedMessage "*couldn't read the saved searches*"
    }

    It 'shows the queries, or says there are none' {
        (& $script:capture { Get-AACSentinelHuntingQuery -WorkspaceId $script:contoso.ResourceId -NoPaging }).Text | Should -Match 'no hunting queries'
        $script:saved = @(& $script:savedSearch 'a' 'Alpha' 'T')
        (& $script:capture { Get-AACSentinelHuntingQuery -WorkspaceId $script:contoso.ResourceId -NoPaging }).Text | Should -Match 'Alpha'
    }

    It 'writes the queries to CSV' {
        $script:saved = @(& $script:savedSearch 'a' 'Alpha' 'T')
        $csv = Join-Path $TestDrive 'installed.csv'
        $null = & $script:capture { Get-AACSentinelHuntingQuery -WorkspaceId $script:contoso.ResourceId -CsvPath $csv }
        @(Import-Csv -LiteralPath $csv).Name | Should -Be 'Alpha'
    }
}

Describe 'Azure Admin Console - Deploy-AACSentinelHuntingQuery' {
    BeforeEach { & $script:mockAzure }

    It 'plans and writes nothing with -WhatIf' {
        $result = Deploy-AACSentinelHuntingQuery -WorkspaceId $script:contoso.ResourceId -Pack SignIn -NoDisplay -WhatIf
        $script:writes.Count | Should -Be 0
        $result.Status | Should -Be 'Planned'
        @($result.Queries | Where-Object Action -EQ 'Create').Count | Should -BeGreaterThan 0
    }

    It 'writes a saved search in the shape Microsoft''s own solutions use' {
        $result = Deploy-AACSentinelHuntingQuery -WorkspaceId $script:contoso.ResourceId -Pack SignIn -Force -NoDisplay
        $result.PSObject.TypeNames[0] | Should -Be 'AAC.SentinelHuntingDeployment'
        $result.Status | Should -Be 'Applied'
        $write = & $script:written $script:contoso.Id.BruteForce
        $write.Method | Should -Be 'Put'
        $write.Uri | Should -Be "$($script:contoso.ResourceId)/savedSearches/$($script:contoso.Id.BruteForce)?api-version=2025-07-01"
        $write.Body.properties.category | Should -Be 'Hunting Queries'
        $write.Body.properties.displayName | Should -Be 'Brute force on sign-ins'
        $write.Body.properties.version | Should -Be 2
        $write.Body.properties.query | Should -Match '\{\{StartTimeISO\}\}' -Because 'Microsoft''s solutions ship the placeholder as it is'
        $write.Body.Contains('etag') | Should -BeFalse -Because 'a new saved search has none'
        $tags = @{}; foreach ($t in $write.Body.properties.tags) { $tags[$t.name] = $t.value }
        $tags['tactics'] | Should -Be 'CredentialAccess,InitialAccess'
        $tags['techniques'] | Should -Be 'T1110'
        $tags['description'] | Should -Match 'Many failed sign-ins'
        $tags['aacVersion'] | Should -Be '1.2.0'
        $tags['aacQueryHash'] | Should -Be (& $script:hash $write.Body.properties.query)
        $tags['aacSource'] | Should -Match 'Hunting Queries/SigninLogs/BruteForce\.yaml$'
    }

    It 'skips what isn''t ready, and -IncludeNotReady deploys it' {
        $result = Deploy-AACSentinelHuntingQuery -WorkspaceId $script:contoso.ResourceId -Pack M365 -Force -NoDisplay
        $cloud = @($result.Queries | Where-Object Name -EQ 'Cloud app policy change')[0]
        $cloud.Action | Should -Be 'Skip'
        $cloud.Reason | Should -Match 'Missing data: CloudAppEvents'
        & $script:written $script:contoso.Id.Cloud | Should -BeNullOrEmpty
        $null = Deploy-AACSentinelHuntingQuery -WorkspaceId $script:contoso.ResourceId -Pack M365 -IncludeNotReady -Force -NoDisplay
        & $script:written $script:contoso.Id.Cloud | Should -Not -BeNullOrEmpty
    }

    It 'updates an unedited query, sending its etag' {
        $script:saved = @(& $script:savedSearch $script:contoso.Id.Mail 'Mail redirect rule' 'old query' @{ aacQueryHash = (& $script:hash 'old query') })
        $result = Deploy-AACSentinelHuntingQuery -WorkspaceId $script:contoso.ResourceId -Pack M365 -Name 'Mail*' -Force -NoDisplay
        $result.Updated | Should -Be 1
        (& $script:written $script:contoso.Id.Mail).Body.etag | Should -Be 'W/"etag-1"'
    }

    It 'leaves an edited query alone - even with -Force - unless -OverwriteChanged' {
        $script:saved = @(& $script:savedSearch $script:contoso.Id.Mail 'Mail redirect rule' 'edited' @{ aacQueryHash = (& $script:hash 'old query') })
        $result = Deploy-AACSentinelHuntingQuery -WorkspaceId $script:contoso.ResourceId -Pack M365 -Name 'Mail*' -Force -NoDisplay
        $result.Skipped | Should -Be 1
        $result.Status | Should -Be 'NoChanges'
        $script:writes.Count | Should -Be 0
        $result = Deploy-AACSentinelHuntingQuery -WorkspaceId $script:contoso.ResourceId -Pack M365 -Name 'Mail*' -OverwriteChanged -Force -NoDisplay
        $result.Updated | Should -Be 1
    }

    It 'never adds a second copy of a query already there under another ID' {
        $script:saved = @(& $script:savedSearch 'Microsoft_365_Hunting_Query_1' 'Mail redirect rule' 'from Content hub')
        $result = Deploy-AACSentinelHuntingQuery -WorkspaceId $script:contoso.ResourceId -Pack M365 -Name 'Mail*' -OverwriteChanged -IncludeNotReady -Force -NoDisplay
        $script:writes.Count | Should -Be 0
        @($result.Queries)[0].Deployment | Should -Be 'Other copy'
    }

    It 'changes nothing the second time' {
        $query = "OfficeActivity`n| where Operation == 'New-TransportRule'"
        $script:saved = @(& $script:savedSearch $script:contoso.Id.Mail 'Mail redirect rule' $query @{ aacQueryHash = (& $script:hash $query) })
        (Deploy-AACSentinelHuntingQuery -WorkspaceId $script:contoso.ResourceId -Pack M365 -Name 'Mail*' -Force -NoDisplay).Status | Should -Be 'NoChanges'
    }

    It 'takes queries from Find, judging them again for this workspace' {
        $found = @(Find-AACSentinelHuntingQuery -Pack M365 -Name 'Mail*' -NoDisplay)
        $found[0].Ready | Should -BeFalse -Because 'Find had no workspace to check'
        $result = $found | Deploy-AACSentinelHuntingQuery -WorkspaceId $script:contoso.ResourceId -Force -NoDisplay
        $result.Created | Should -Be 1
        & $script:written $script:contoso.Id.Mail | Should -Not -BeNullOrEmpty
    }

    It 'can deploy Intune''s queries before its logs arrive, but not by accident' {
        $result = Deploy-AACSentinelHuntingQuery -WorkspaceId $script:contoso.ResourceId -Pack Intune -Force -NoDisplay
        $result.Created | Should -Be 2 -Because 'only IntuneAuditLogs has data here'
        $script:writes.Clear()
        (Deploy-AACSentinelHuntingQuery -WorkspaceId $script:contoso.ResourceId -Pack Intune -IncludeNotReady -Force -NoDisplay).Created | Should -Be 4
    }

    It 'writes nothing when Sentinel isn''t enabled, and says what to do' {
        $script:onboarding = @{ Status = 404; Error = 'Not found'; Body = $null; Items = $null }
        { $null = & $script:capture { Deploy-AACSentinelHuntingQuery -WorkspaceId $script:contoso.ResourceId -Pack Intune -Force -NoDisplay } } | Should -Throw -ExpectedMessage '*Microsoft Sentinel is not enabled*'
        $script:writes.Count | Should -Be 0
    }

    It 'writes nothing when it can''t see what is on the workspace' {
        $script:savedError = 'Forbidden'
        { $null = & $script:capture { Deploy-AACSentinelHuntingQuery -WorkspaceId $script:contoso.ResourceId -Pack Intune -IncludeNotReady -Force -NoDisplay } } | Should -Throw -ExpectedMessage "*couldn't read the saved searches*"
        $script:writes.Count | Should -Be 0
    }

    It 'carries on past a failed write, then says which failed' {
        $script:writeFails = 'Intune - burst of device wipes, retires or deletes by one identity'
        { $null = & $script:capture { Deploy-AACSentinelHuntingQuery -WorkspaceId $script:contoso.ResourceId -Pack Intune -IncludeNotReady -Force -NoDisplay } } | Should -Throw -ExpectedMessage "*couldn't write 1 hunting query*burst of device wipes*"
        $script:writes.Count | Should -Be 3
    }

    It 'shows the whole plan at the prompt with -WhatIf, and writes nothing' {
        # Under -WhatIf, some cmdlets quietly return nothing: the plan must still fill.
        $text = (& $script:capture { Deploy-AACSentinelHuntingQuery -WorkspaceId $script:contoso.ResourceId -Pack M365 -WhatIf }).Text
        foreach ($expected in 'to create', 'Mail redirect rule', 'Sign-in then mailbox access', 'Cloud app policy change', 'Missing data: CloudAppEvents') { $text | Should -Match ([regex]::Escape($expected)) }
        $script:writes.Count | Should -Be 0
    }

    It 'shows the plan, and what happened' {
        $text = (& $script:capture { Deploy-AACSentinelHuntingQuery -WorkspaceId $script:contoso.ResourceId -Pack M365 -Force }).Text
        foreach ($expected in 'to create', 'Mail redirect rule', 'Cloud app policy change', 'Missing data', 'written to law-contoso-sentinel', 'Applied') { $text | Should -Match ([regex]::Escape($expected)) }
    }
}

Describe 'Azure Admin Console - the Intune hunting queries' {
    It 'read only columns Azure Monitor documents for their table: <Name>' -ForEach @(
        @{ Name = 'burst'; Pattern = 'burst'; Columns = @('OperationName', 'Identity', 'TimeGenerated') }
        @{ Name = 'policy'; Pattern = 'policy'; Columns = @('OperationName', 'Identity', 'ResultType', 'CorrelationId', 'Properties', 'TimeGenerated') }
        @{ Name = 'enrollment'; Pattern = 'enrollment'; Columns = @('OperationName', 'Result', 'TimeGenerated') }
        @{ Name = 'devices'; Pattern = 'jailbroken'; Columns = @('DeviceId', 'JailBroken', 'CompliantState', 'DeviceName', 'UPN', 'OS', 'OSVersion', 'EncryptionStatusString', 'LastContact', 'Ownership', 'TimeGenerated') }
    ) {
        $queries = @(InModuleScope 'Azure.Admin.Console' { Get-AACIntuneHuntingQuery })
        $query = @($queries | Where-Object { $_.Name -match $Pattern })[0].Query
        foreach ($column in $Columns) { $query | Should -Match "\b$column\b" }
    }
}
