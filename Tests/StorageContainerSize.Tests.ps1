<#
    Unit tests for Get-AACStorageAccountContainerSize: the List Blobs page
    parser (ConvertFrom-AACBlobList) on made-up pages, Azure Storage's XML
    errors, and the command with Resource Graph, Resource Manager and the
    blob service faked - paging, the access tiers, the largest blobs, what
    can't be read and why, -AuthMode Auto falling back to an account SAS,
    the filters, the view and the exports.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
}

BeforeAll {
    # A <Blob> element as Azure Storage writes it.
    $script:blob = {
        param([string] $Name, [long] $Size, [string] $Tier = 'Hot', [string] $Extra = '', [string] $Type = 'BlockBlob', [string] $Modified = 'Tue, 01 Sep 2026 10:00:00 GMT', [string] $Properties = '')
        $tier = if ($Tier) { "<AccessTier>$Tier</AccessTier><AccessTierInferred>true</AccessTierInferred>" } else { '' }
        "<Blob><Name>$Name</Name>$Extra<Properties><Creation-Time>Mon, 01 Jun 2026 08:00:00 GMT</Creation-Time><Last-Modified>$Modified</Last-Modified><Etag>0x8DCB</Etag><Content-Length>$Size</Content-Length><Content-Type>application/octet-stream</Content-Type><Content-MD5 /><BlobType>$Type</BlobType>$tier$Properties<LeaseStatus>unlocked</LeaseStatus></Properties><OrMetadata /></Blob>"
    }
    $script:page = {
        param([string[]] $Blobs, [string] $Next = '')
        $marker = if ($Next) { "<NextMarker>$Next</NextMarker>" } else { '<NextMarker />' }
        "<?xml version=`"1.0`" encoding=`"utf-8`"?><EnumerationResults ServiceEndpoint=`"https://x.blob.core.windows.net/`" ContainerName=`"c`"><MaxResults>5000</MaxResults><Blobs>$($Blobs -join '')</Blobs>$marker</EnumerationResults>"
    }
    $script:parse = {
        param([string] $Content, [int] $Top = 3, [switch] $KeepBlob)
        InModuleScope 'Azure.Admin.Console' -Parameters @{ C = $Content; T = $Top; K = [bool]$KeepBlob } {
            param($C, $T, $K)
            $tally = New-AACBlobTally -KeepBlob:$K
            $next = ConvertFrom-AACBlobList -Content $C -State $tally -Top $T -StorageAccount 'st' -Container 'c'
            @{ Tally = $tally; Next = $next }
        }
    }
    $script:capture = {
        param([scriptblock] $Render, [switch] $Ascii)
        $real = [Spectre.Console.AnsiConsole]::Console
        $buffer = [System.IO.StringWriter]::new()
        $settings = [Spectre.Console.AnsiConsoleSettings]::new()
        $settings.Out = [Spectre.Console.AnsiConsoleOutput]::new($buffer)
        $settings.Ansi = [Spectre.Console.AnsiSupport]::No
        $settings.Enrichment.UseDefaultEnrichers = $false
        $console = [Spectre.Console.AnsiConsole]::Create($settings)
        $console.Profile.Width = 180
        $console.Profile.Capabilities.Unicode = -not $Ascii
        try { [Spectre.Console.AnsiConsole]::Console = $console; $output = @(& $Render) }
        finally { [Spectre.Console.AnsiConsole]::Console = $real }
        [pscustomobject]@{ Text = $buffer.ToString(); Output = $output }
    }
}

Describe 'Azure Admin Console - List Blobs pages' {
    It 'adds up the blobs, their tiers and the newest change, and returns the next marker' {
        $content = & $script:page @(
            (& $script:blob 'a.log' 100 'Hot')
            (& $script:blob 'b.log' 2048 'Cool' -Modified 'Wed, 30 Sep 2026 12:30:00 GMT')
            (& $script:blob 'c.bak' 5000 'Archive')
            (& $script:blob 'disk.vhd' 4096 '' -Type 'PageBlob')
        ) -Next '2!88!MDAwMDE2IWIubG9n'
        $r = & $script:parse $content
        $r.Next | Should -BeExactly '2!88!MDAwMDE2IWIubG9n'
        $r.Tally.Blobs | Should -Be 4
        $r.Tally.Bytes | Should -Be 11244
        $r.Tally.Tiers['Hot'][1] | Should -Be 100
        $r.Tally.Tiers['Cool'][1] | Should -Be 2048
        $r.Tally.Tiers['Archive'][1] | Should -Be 5000
        $r.Tally.Tiers['None'][1] | Should -Be 4096 -Because 'page blobs have no access tier'
        $r.Tally.LastModified | Should -Be ([datetime]::new(2026, 9, 30, 12, 30, 0, [System.DateTimeKind]::Utc))
        $r.Tally.Pages | Should -Be 1
    }

    It 'keeps only the -Top largest blobs, with their names decoded' {
        $content = & $script:page @(
            (& $script:blob 'small' 1)
            (& $script:blob 'R&amp;D/plan.docx' 900)
            (& $script:blob 'mid' 500)
            (& $script:blob 'big' 1000)
            (& $script:blob 'tiny' 2)
        )
        $r = & $script:parse $content -Top 2
        $r.Next | Should -BeExactly ''
        @($r.Tally.Largest | Sort-Object Size -Descending | ForEach-Object Name) | Should -Be @('big', 'R&D/plan.docx')
        $r.Tally.Largest[0].GetType().FullName | Should -Be 'AzureAdminConsole.StorageBlob'
        $r.Tally.Rows | Should -BeNullOrEmpty -Because 'blobs are kept only with -KeepBlob'
    }

    It 'decodes percent-encoded names' {
        $content = & $script:page @('<Blob><Name Encoded="true">odd%01name</Name><Properties><Content-Length>7</Content-Length><BlobType>BlockBlob</BlobType><AccessTier>Hot</AccessTier></Properties></Blob>')
        $r = & $script:parse $content -KeepBlob
        $r.Tally.Rows[0].Name | Should -BeExactly "odd$([char]1)name"
    }

    It 'counts snapshots, previous versions, deleted blobs and Data Lake directories on their own' {
        $content = & $script:page @(
            (& $script:blob 'doc' 10 -Extra '<VersionId>2026-09-02T00:00:00Z</VersionId><IsCurrentVersion>true</IsCurrentVersion>')
            (& $script:blob 'doc' 8 -Extra '<VersionId>2026-09-01T00:00:00Z</VersionId>')
            (& $script:blob 'doc' 6 -Extra '<Snapshot>2026-08-01T00:00:00.0000000Z</Snapshot>')
            (& $script:blob 'gone' 4 -Extra '<Deleted>true</Deleted>')
            (& $script:blob 'folder' 0 '' -Properties '<ResourceType>directory</ResourceType>')
        )
        $r = & $script:parse $content -KeepBlob
        $r.Tally.Blobs | Should -Be 1
        $r.Tally.Bytes | Should -Be 10
        $r.Tally.Versions | Should -Be 1
        $r.Tally.VersionBytes | Should -Be 8
        $r.Tally.Snapshots | Should -Be 1
        $r.Tally.SnapshotBytes | Should -Be 6
        $r.Tally.Deleted | Should -Be 1
        $r.Tally.DeletedBytes | Should -Be 4
        $r.Tally.Directories | Should -Be 1
        @($r.Tally.Rows | ForEach-Object Kind) | Should -Be @('Blob', 'Version', 'Snapshot', 'Deleted')
        $r.Tally.Rows[0].SizeText | Should -Be '10 B'
    }

    It 'reads a page of 5,000 blobs quickly' {
        $content = & $script:page @(1..5000 | ForEach-Object { & $script:blob "folder/blob-$_.parquet" ($_ * 1024) $(if ($_ % 2) { 'Hot' } else { 'Cool' }) })
        $clock = [System.Diagnostics.Stopwatch]::StartNew()
        $r = & $script:parse $content
        $clock.Stop()
        $r.Tally.Blobs | Should -Be 5000
        $r.Tally.Bytes | Should -Be (1024L * 5000 * 5001 / 2)
        $clock.Elapsed.TotalSeconds | Should -BeLessThan 5
    }

    It "turns Azure Storage's XML error into its code and message" {
        $xml = "<?xml version=`"1.0`" encoding=`"utf-8`"?><Error><Code>AuthorizationPermissionMismatch</Code><Message>This request is not authorized to perform this operation using this permission.`nRequestId:abc`nTime:2026-10-01T10:00:00Z</Message></Error>"
        InModuleScope 'Azure.Admin.Console' -Parameters @{ X = $xml } { param($X) Get-AACErrorMessage -Content $X -Fallback 'HTTP 403' } |
            Should -BeExactly 'AuthorizationPermissionMismatch: This request is not authorized to perform this operation using this permission.'
    }

    It 'formats sizes in powers of 1,024' {
        InModuleScope 'Azure.Admin.Console' {
            Format-AACByteSize -Bytes 0 | Should -Be '0 B'
            Format-AACByteSize -Bytes 1023 | Should -Be '1,023 B'
            Format-AACByteSize -Bytes 1536 | Should -Be '1.50 KiB'
            Format-AACByteSize -Bytes ([Math]::Pow(1024, 4) * 2.5) | Should -Be '2.50 TiB'
            Format-AACByteSize -Bytes (5MB) -Unit 'GiB' -Decimals 3 | Should -Be '0.005 GiB'
        }
    }
}

Describe 'Azure Admin Console - Get-AACStorageAccountContainerSize' {
    BeforeAll {
        $script:sub = '11111111-1111-1111-1111-111111111111'
        $id = { param([string] $Name, [string] $Group = 'rg-data') "/subscriptions/$script:sub/resourceGroups/$Group/providers/Microsoft.Storage/storageAccounts/$Name" }
        $account = {
            param([string] $Name, [string] $Kind = 'StorageV2', [string] $SharedKey = '', [string] $Group = 'rg-data', [switch] $NoBlob, [string] $DefaultAction = 'Allow')
            @{
                id = (& $id $Name $Group); name = $Name; resourceGroup = $Group; subscriptionId = $script:sub; location = 'uksouth'; kind = $Kind; sku = 'Standard_LRS'
                blob = $(if ($NoBlob) { '' } else { "https://$Name.blob.core.windows.net/" }); hns = 'False'; sharedKey = $SharedKey; publicNetwork = 'Enabled'; defaultAction = $DefaultAction
            }
        }
        $script:accounts = @(
            (& $account 'stdata')
            (& $account 'stlocked')
            (& $account 'stnokey' -SharedKey 'False')
            (& $account 'stfirewall' -DefaultAction 'Deny')
            (& $account 'stfiles' -Kind 'FileStorage' -NoBlob)
            (& $account 'stother' -Group 'rg-other')
        )
        $script:containers = @{
            stdata     = @('logs', 'backups', 'empty', '$web')
            stlocked   = @('secret')
            stnokey    = @('x')
            stfirewall = @('y')
            stother    = @('misc')
        }
        $blob = $script:blob
        $page = $script:page
        # Each container's pages, by marker ('' is the first).
        $script:pages = @{
            'stdata/logs'      = @{ '' = (& $page @((& $blob 'app/2026-09-01.log' 1000 'Hot'), (& $blob 'app/2026-09-02.log' 3000 'Hot')) -Next 'm1'); 'm1' = (& $page @((& $blob 'app/2026-09-03.log' 6000 'Cool')) ) }
            'stdata/backups'   = @{ '' = (& $page @((& $blob 'db/full.bak' 50000 'Archive'), (& $blob 'db/diff.bak' 20000 'Cool'))) }
            'stdata/empty'     = @{ '' = (& $page @()) }
            'stdata/$web'      = @{ '' = (& $page @((& $blob 'index.html' 10 'Hot'))) }
            'stlocked/secret'  = @{ '' = (& $page @((& $blob 'keys.json' 700 'Hot'))) }
            'stother/misc'     = @{ '' = (& $page @((& $blob 'a' 1 'Hot'))) }
        }
        $script:respond = {
            param([int] $Status, [string] $Body)
            $response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]$Status)
            $response.Content = [System.Net.Http.StringContent]::new($Body)
            [System.Threading.Tasks.Task]::FromResult($response)
        }
        $script:denied = { param([string] $Code, [string] $Message) "<?xml version=`"1.0`" encoding=`"utf-8`"?><Error><Code>$Code</Code><Message>$Message`nRequestId:1</Message></Error>" }
    }

    BeforeEach {
        $script:sent = [System.Collections.Generic.List[object]]::new()
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACGraphBatch -MockWith {
            $rows = @{ subscriptions = @(@{ subscriptionId = $script:sub; name = 'sub-contoso' }); accounts = @($script:accounts) }
            if ($Query['accounts'] -match 'resourceGroup in~') { $rows.accounts = @($script:accounts | Where-Object { $_.resourceGroup -eq 'rg-other' }) }
            if ($OnProgress) { & $OnProgress 'accounts' 2 2 }
            @{ Rows = $rows; Errors = @{} }
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACArmParallel -MockWith {
            $out = @{}
            foreach ($u in $Uri) {
                $name = ($u -split '/')[8]
                $out[$u] = @{ Status = 200; Body = $null; Error = ''; Items = [System.Collections.Generic.List[object]]@(@($script:containers[$name]) | ForEach-Object { @{ name = $_; properties = @{ publicAccess = $(if ($_ -eq '$web') { 'Blob' } else { 'None' }) } } }) }
            }
            $out
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Send-AACHttpRequest -MockWith {
            $script:sent.Add([pscustomobject]@{ Method = $Method; Uri = $Uri; Token = $Token; Version = $(if ($Header) { $Header['x-ms-version'] }) })
            if ($Uri -match '/listAccountSas') {
                if ($Uri -match 'stfirewall') { return (& $script:respond 403 '{"error":{"code":"AuthorizationFailed","message":"The client does not have authorization to perform action Microsoft.Storage/storageAccounts/listAccountSas/action."}}') }
                return (& $script:respond 200 '{"accountSasToken":"sv=2023-11-03&ss=b&srt=co&sp=rl&sig=fake"}')
            }
            $u = [uri]$Uri
            $account = $u.Host.Split('.')[0]
            $container = [uri]::UnescapeDataString($u.AbsolutePath.Trim('/'))
            $query = @{}
            foreach ($pair in $u.Query.TrimStart('?').Split('&')) { $kv = $pair.Split('=', 2); $query[$kv[0]] = [uri]::UnescapeDataString($kv[1]) }
            $withSas = [bool]$query['sig']
            if ($account -eq 'stfirewall') { return (& $script:respond 403 (& $script:denied 'AuthorizationFailure' 'This request is not authorized to perform this operation.')) }
            if ($account -in 'stlocked', 'stnokey' -and -not $withSas) { return (& $script:respond 403 (& $script:denied 'AuthorizationPermissionMismatch' 'This request is not authorized to perform this operation using this permission.')) }
            $marker = if ($query['marker']) { $query['marker'] } else { '' }
            & $script:respond 200 $script:pages["$account/$container"][$marker]
        }
        InModuleScope 'Azure.Admin.Console' { $script:AACSession = [pscustomobject]@{ Account = 'admin@contoso.com'; TenantId = 't'; AccessToken = 'x'; ExpiresOn = (Get-Date).AddHours(1); RefreshToken = 'r'; ClientId = 'c'; Scope = @('s') } }
    }
    AfterEach { InModuleScope 'Azure.Admin.Console' { $script:AACSession = $null } }

    It 'sizes every container, following the pages, with Entra ID by default' {
        $rows = @(Get-AACStorageAccountContainerSize -NoDisplay)
        $logs = $rows | Where-Object { $_.StorageAccount -eq 'stdata' -and $_.Container -eq 'logs' }
        $logs.Status | Should -Be 'OK'
        $logs.BlobCount | Should -Be 3
        $logs.Size | Should -Be 10000
        $logs.SizeHot | Should -Be 4000
        $logs.SizeCool | Should -Be 6000
        $logs.AuthMode | Should -Be 'Entra ID'
        $logs.PSObject.TypeNames[0] | Should -Be 'AAC.StorageContainerSize'
        $backups = $rows | Where-Object Container -EQ 'backups'
        $backups.SizeArchive | Should -Be 50000
        $backups.LargestBlobs[0].Name | Should -Be 'db/full.bak'
        ($rows | Where-Object Container -EQ 'empty').BlobCount | Should -Be 0
        ($rows | Where-Object Container -EQ '$web').PublicAccess | Should -Be 'Blob'
        @($script:sent | Where-Object { $_.Uri -like 'https://stdata.blob.core.windows.net/logs?*' }).Count | Should -Be 2 -Because 'the second page is read with the first one''s marker'
        @($script:sent | Where-Object { $_.Uri -like '*marker=m1*' }).Count | Should -Be 1
        @($script:sent | Where-Object { $_.Uri -like '*.blob.core.windows.net/*' } | ForEach-Object Token | Select-Object -Unique) | Should -Be @('fake-token')
        @($script:sent | Where-Object { $_.Uri -like '*.blob.core.windows.net/*' } | ForEach-Object Version | Select-Object -Unique) | Should -Be @('2023-11-03')
        Should -Invoke -ModuleName 'Azure.Admin.Console' Get-AACAccessToken -ParameterFilter { $Resource -eq 'https://storage.azure.com' }
        @($script:sent | Where-Object Uri -Like '*listAccountSas*').Count | Should -Be 0 -Because 'no SAS is made unless -AuthMode asks for it'
        $rows | Where-Object StorageAccount -EQ 'stfiles' | Should -BeNullOrEmpty -Because 'a file shares account has no blob service'
    }

    It 'says why a container could not be read, and what to do' {
        $rows = @(Get-AACStorageAccountContainerSize -NoDisplay)
        $locked = $rows | Where-Object StorageAccount -EQ 'stlocked'
        $locked.Status | Should -Be 'Failed'
        $locked.Error | Should -BeLike 'AuthorizationPermissionMismatch:*Storage Blob Data Reader*'
        ($rows | Where-Object StorageAccount -EQ 'stfirewall').Error | Should -BeLike "AuthorizationFailure:*firewall refused this network (Selected networks)*"
        $open = InModuleScope 'Azure.Admin.Console' {
            ConvertTo-AACStorageContainerRow -Item @{ Account = [ordered]@{ Name = 'st'; Firewall = 'All networks'; Id = 'x'; Hns = $false; ResourceGroup = 'rg'; SubscriptionName = 's'; SubscriptionId = 's'; Location = 'uksouth'; Kind = 'StorageV2'; Sku = 'Standard_LRS' }; Container = 'c'; Url = ''; PublicAccess = 'None'; AuthMode = 'Entra ID'; Tally = $null; Error = 'AuthorizationFailure: This request is not authorized to perform this operation.' }
        }
        $open.Error | Should -BeLike '*private endpoint*' -Because 'an account open to all networks points elsewhere'
        $open.Status | Should -Be 'Failed'
    }

    It 'falls back to an account SAS with -AuthMode Auto - only where Entra ID lacks a data role and shared keys are allowed' {
        $rows = @(Get-AACStorageAccountContainerSize -AuthMode Auto -NoDisplay)
        $locked = $rows | Where-Object StorageAccount -EQ 'stlocked'
        $locked.Status | Should -Be 'OK'
        $locked.Size | Should -Be 700
        $locked.AuthMode | Should -Be 'Account SAS'
        ($rows | Where-Object StorageAccount -EQ 'stnokey').Error | Should -BeLike 'KeyBasedAuthenticationNotPermitted*'
        ($rows | Where-Object StorageAccount -EQ 'stfirewall').Error | Should -BeLike 'AuthorizationFailure*' -Because 'an account SAS gets no further through a firewall'
        @($script:sent | Where-Object Uri -Like '*listAccountSas*' | ForEach-Object { ($_.Uri -split '/')[8] }) | Should -Be @('stlocked')
        $sasRead = @($script:sent | Where-Object { $_.Uri -like 'https://stlocked.blob.core.windows.net/*sig=*' })
        $sasRead.Count | Should -Be 1
        $sasRead[0].Token | Should -BeNullOrEmpty -Because 'a SAS request carries no bearer token'
        ($rows | Where-Object StorageAccount -EQ 'stdata' | Select-Object -First 1).AuthMode | Should -Be 'Entra ID'
        $rows | ForEach-Object { $_.Url | Should -Not -BeLike '*sig=*' -Because 'the SAS is never written into the rows' }
    }

    It 'reads every account with an account SAS with -AuthMode AccountSas' {
        $rows = @(Get-AACStorageAccountContainerSize -AuthMode AccountSas -StorageAccountName 'stdata' -NoDisplay)
        @($rows | ForEach-Object AuthMode | Select-Object -Unique) | Should -Be @('Account SAS')
        ($rows | Measure-Object -Property Size -Sum).Sum | Should -Be 80010
        Should -Invoke -ModuleName 'Azure.Admin.Console' Get-AACAccessToken -Times 0 -ParameterFilter { $Resource -eq 'https://storage.azure.com' }
    }

    It 'filters storage accounts, containers and resource groups' {
        @(Get-AACStorageAccountContainerSize -StorageAccountName 'stdat*' -ContainerName 'log*', 'back*' -NoDisplay | ForEach-Object Container | Sort-Object) | Should -Be @('backups', 'logs')
        @(Get-AACStorageAccountContainerSize -ResourceGroupName 'rg-other' -NoDisplay | ForEach-Object StorageAccount) | Should -Be @('stother')
        { Get-AACStorageAccountContainerSize -StorageAccountName 'nope' -NoDisplay } | Should -Throw '*No storage account named*nope*'
    }

    It 'keeps every blob with -IncludeBlob' {
        $rows = @(Get-AACStorageAccountContainerSize -StorageAccountName 'stdata' -ContainerName 'logs' -IncludeBlob -NoDisplay)
        @($rows[0].Blobs | ForEach-Object Name) | Should -Be @('app/2026-09-01.log', 'app/2026-09-02.log', 'app/2026-09-03.log')
        $rows[0].Blobs[2].AccessTier | Should -Be 'Cool'
    }

    It 'asks the blob service for snapshots, versions and deleted blobs only when told' {
        $null = Get-AACStorageAccountContainerSize -StorageAccountName 'stother' -IncludeSnapshot -IncludeVersion -IncludeDeleted -NoDisplay
        @($script:sent | Where-Object { $_.Uri -like '*include=snapshots,versions,deleted*' }).Count | Should -Be 1
    }

    It 'shows tiles, the tiers, the tree of accounts and containers, the largest blobs and what was not read' {
        $text = (& $script:capture { Get-AACStorageAccountContainerSize -NoPaging }).Text
        $text | Should -Match 'storage accounts'
        $text | Should -Match 'Size by access tier'
        $text | Should -Match 'Largest containers'
        $text | Should -Match 'stdata'
        $text | Should -Match 'backups'
        $text | Should -Match 'db/full\.bak'
        $text | Should -Match '48\.83 KiB'
        $text | Should -Match 'AuthorizationPermissionMismatch'
        $text | Should -Match 'Not read in full'
        $ascii = (& $script:capture { Get-AACStorageAccountContainerSize -NoPaging } -Ascii).Text
        $ascii | Should -Match '#'
    }

    It 'writes the containers and every blob to CSV, and an HTML report' {
        $csv = Join-Path $TestDrive 'containers.csv'
        $blobs = Join-Path $TestDrive 'blobs.csv'
        $html = Join-Path $TestDrive 'storage.html'
        $null = & $script:capture { Get-AACStorageAccountContainerSize -StorageAccountName 'stdata' -CsvPath $csv -BlobCsvPath $blobs -HtmlPath $html }
        $rows = @(Import-Csv -LiteralPath $csv)
        $rows.Count | Should -Be 4
        $rows[0].PSObject.Properties.Name | Should -Not -Contain 'LargestBlobs'
        $blobRows = @(Import-Csv -LiteralPath $blobs)
        $blobRows.Count | Should -Be 6
        ($blobRows | Where-Object Name -EQ 'db/full.bak').SizeText | Should -Be '48.83 KiB'
        $html | Should -Exist
        Get-Content -LiteralPath $html -Raw | Should -Match 'db/full.bak'
    }
}
