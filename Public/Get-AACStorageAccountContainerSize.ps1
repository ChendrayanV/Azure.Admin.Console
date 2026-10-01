function Get-AACStorageAccountContainerSize {
    <#
    .EXTERNALHELP Azure.Admin.Console-help.xml
    .SYNOPSIS
        How much is stored in every blob container of your storage accounts -
        blobs, bytes, access tiers and the largest blobs - with a
        Spectre.Console view, objects, and CSV and interactive HTML reports.
    .DESCRIPTION
        Finds the storage accounts with Azure Resource Graph, lists their
        containers through Azure Resource Manager (Reader is enough), then
        lists every blob of every container from the blob service itself and
        adds them up. Without parameters it reads every storage account the
        account can see.

        Fast on large estates: the containers are read side by side - 16 at
        a time by default (-ThrottleLimit), over pooled HTTPS connections -
        each a page of 5,000 blobs at a time. Each page is read by a parser
        compiled on first use (about 275,000 blobs a second), added up and
        dropped as it arrives, so memory stays flat however many blobs there
        are (unless -IncludeBlob or -BlobCsvPath keep every one). Throttling
        is retried as Azure Storage asks.

        Reading blobs needs data access, which Reader alone doesn't give.
        -AuthMode picks how:
          EntraId     (default) your Connect-AAC sign-in, with a token for
                      Azure Storage - you need the Storage Blob Data Reader
                      role (or Contributor or Owner of the data) on the
                      account, its resource group or subscription
          AccountSas  a read-and-list account SAS for the blob service, valid
                      for 4 hours, from Azure Resource Manager's
                      listAccountSas - you need permission to list the
                      account's keys (Contributor, Storage Account
                      Contributor); not for accounts that don't allow shared
                      key access. The SAS is kept in memory only, never shown
                      or written.
          Auto        Entra ID first; the accounts that refuse it for want of
                      a data role are then read with an account SAS
        Accounts behind a firewall or private endpoint can only be read from
        a network they allow; they are reported as such.

        One row per container (AAC.StorageContainerSize): StorageAccount,
        Container, Status (OK, Partial, Failed), BlobCount, Size (bytes, of
        the current blobs) and SizeText, SizeHot, SizeCool, SizeCold,
        SizeArchive and SizeNoTier (page, append and premium blobs),
        Snapshots, Versions and DeletedBlobs with their sizes (when listed),
        TotalSize (all of it), Directories (Data Lake Storage), LastModified
        (the newest blob), PublicAccess, AuthMode, Error (with what to do),
        ResourceGroup, SubscriptionName, Location, Kind, Sku, Url,
        LargestBlobs (the -Top largest) and, with -IncludeBlob, Blobs (every
        blob) - as AzureAdminConsole.StorageBlob objects: Name, Size,
        SizeText, AccessTier, BlobType, Kind, LastModified. An account whose
        containers couldn't be listed is one row with no Container and its
        reason.

        What you get depends on where the command runs:
          at the prompt    tiles, the size by access tier, the largest
                           containers as a chart, every account with its
                           containers as a tree (a size bar each), the
                           largest blobs and what couldn't be read - a page
                           at a time
          piped onward     the container rows, with no view
          -PassThru        the view and the rows
          -NoDisplay       the rows only
        -CsvPath writes the container rows, -BlobCsvPath every blob listed.
        -HtmlPath writes an interactive report: tiles, charts, and tables of
        the accounts, containers and largest blobs - searchable, filterable
        and downloadable as CSV. With any of them, the console shows only the
        progress and the files written.
    .PARAMETER SubscriptionId
        Only these subscriptions.
    .PARAMETER ResourceGroupName
        Only storage accounts in these resource groups.
    .PARAMETER StorageAccountName
        Only these storage accounts; wildcards work, e.g. 'stlogs*'.
    .PARAMETER ContainerName
        Only these containers; wildcards work, e.g. 'backup-*'.
    .PARAMETER AuthMode
        How blobs are read: EntraId (the default, needs a data role such as
        Storage Blob Data Reader), AccountSas (a short-lived read-only
        account SAS, needs permission to list keys) or Auto (Entra ID, then
        an account SAS where Entra ID is refused).
    .PARAMETER IncludeSnapshot
        List blob snapshots too; they are counted and sized on their own.
    .PARAMETER IncludeVersion
        List previous blob versions too (accounts with versioning).
    .PARAMETER IncludeDeleted
        List soft-deleted blobs too.
    .PARAMETER IncludeBlob
        Keep every blob listed, on each row's Blobs property. Takes memory
        in proportion to the number of blobs (a few hundred bytes each).
    .PARAMETER Top
        How many of the largest blobs to keep per container (10; 0 for none).
    .PARAMETER ThrottleLimit
        How many containers to read at once (16; 1 to 64).
    .PARAMETER CsvPath
        Write the container rows to this CSV file.
    .PARAMETER BlobCsvPath
        Write every blob listed to this CSV file (implies keeping them, as
        -IncludeBlob does).
    .PARAMETER HtmlPath
        Write an interactive HTML report to this file.
    .PARAMETER Title
        The HTML report's title.
    .PARAMETER PassThru
        Show the view and also return the rows.
    .PARAMETER NoDisplay
        Return the rows without showing the view.
    .PARAMETER NoPaging
        Show the whole view at once instead of a page at a time.
    .EXAMPLE
        Connect-AAC
        Get-AACStorageAccountContainerSize
        Every container of every storage account you can see, with its size.
    .EXAMPLE
        Get-AACStorageAccountContainerSize -StorageAccountName 'stlogs*' -ContainerName 'insights-*' -AuthMode Auto
        The insights containers of the 'stlogs' accounts, read with Entra ID or, where that is refused, an account SAS.
    .EXAMPLE
        Get-AACStorageAccountContainerSize -NoDisplay | Sort-Object Size -Descending | Select-Object -First 10 StorageAccount, Container, BlobCount, SizeText
        The ten largest containers.
    .EXAMPLE
        Get-AACStorageAccountContainerSize -StorageAccountName 'stbackup01' -BlobCsvPath .\out\Blobs.csv -HtmlPath .\out\Storage.html
        Every blob of one account to CSV, and an interactive HTML report.
    .EXAMPLE
        (Get-AACStorageAccountContainerSize -NoDisplay -Top 5).LargestBlobs | Sort-Object Size -Descending | Select-Object -First 20
        The 20 largest blobs across every account.
    .OUTPUTS
        AAC.StorageContainerSize (piped onward, or with -PassThru or -NoDisplay)
    #>
    [CmdletBinding()]
    [OutputType('AAC.StorageContainerSize')]
    param(
        [ValidatePattern('^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$')]
        [string[]] $SubscriptionId,

        [ValidateNotNullOrEmpty()]
        [string[]] $ResourceGroupName,

        [SupportsWildcards()]
        [ValidateNotNullOrEmpty()]
        [string[]] $StorageAccountName,

        [SupportsWildcards()]
        [ValidateNotNullOrEmpty()]
        [string[]] $ContainerName,

        [ValidateSet('EntraId', 'AccountSas', 'Auto')]
        [string] $AuthMode = 'EntraId',

        [switch] $IncludeSnapshot,

        [switch] $IncludeVersion,

        [switch] $IncludeDeleted,

        [switch] $IncludeBlob,

        [ValidateRange(0, 1000)]
        [int] $Top = 10,

        [ValidateRange(1, 64)]
        [int] $ThrottleLimit = 16,

        [string] $CsvPath,

        [string] $BlobCsvPath,

        [string] $HtmlPath,

        [string] $Title = 'Storage account container sizes',

        [switch] $PassThru,

        [switch] $NoDisplay,

        [switch] $NoPaging
    )

    # A failure anywhere below ends as a Spectre.Console error panel and this
    # command's own terminating error, not a line inside the module. A stopped
    # pipeline (Select-Object -First, Ctrl+C) is no failure: just return - a
    # rethrow would stop the caller's whole script, not only this command.
    trap { if ($_.Exception -is [System.Management.Automation.PipelineStoppedException]) { return }; $PSCmdlet.ThrowTerminatingError((Show-AACError -ErrorRecord $_ -Cmdlet $PSCmdlet)) }

    $pipedOnward = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength
    $interactive = -not $NoDisplay -and -not $pipedOnward
    $showView = $interactive -and -not ($CsvPath -or $BlobCsvPath -or $HtmlPath)
    $returnObjects = $PassThru -or $NoDisplay -or $pipedOnward
    $resolve = { param([string] $Path) if ($Path) { $PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path) } }
    $csvFullPath = & $resolve $CsvPath
    $blobCsvFullPath = & $resolve $BlobCsvPath
    $htmlFullPath = & $resolve $HtmlPath
    $keepBlob = $IncludeBlob -or $BlobCsvPath
    $include = @(if ($IncludeSnapshot) { 'snapshots' }; if ($IncludeVersion) { 'versions' }; if ($IncludeDeleted) { 'deleted' })
    $quote = { param([string] $Text) "'" + ($Text -replace '\\', '\\' -replace "'", "\'") + "'" }
    $groupFilter = if ($ResourceGroupName) { " | where resourceGroup in~ ($((@($ResourceGroupName | ForEach-Object { & $quote $_ })) -join ', '))" } else { '' }
    $matchesAny = { param([string] $Value, [string[]] $Pattern) foreach ($p in $Pattern) { if ($Value -like $p) { return $true } }; $false }

    if ($interactive) {
        Write-AACRule -Title 'Azure Admin Console :: Storage account container sizes' -Color 'deepskyblue3_1'
    }
    $state = Invoke-AACProgress -ScriptBlock {
        $null = Get-AACAccessToken
        $clock = [System.Diagnostics.Stopwatch]::StartNew()

        # --- The storage accounts (Resource Graph) ----------------------------------------------------
        Update-AACProgress -Id 'read' -Total 2 -Description 'Finding the storage accounts'
        $batch = Invoke-AACGraphBatch -SubscriptionId $SubscriptionId -Query ([ordered]@{
                subscriptions = "resourcecontainers | where type =~ 'microsoft.resources/subscriptions' | project subscriptionId, name"
                accounts      = "resources | where type =~ 'microsoft.storage/storageaccounts'$groupFilter | project id, name, resourceGroup, subscriptionId, location, kind, sku = tostring(sku.name), blob = tostring(properties.primaryEndpoints.blob), hns = tobool(properties.isHnsEnabled), sharedKey = tostring(properties.allowSharedKeyAccess), publicNetwork = tostring(properties.publicNetworkAccess), defaultAction = tostring(properties.networkAcls.defaultAction)"
            }) -OnProgress { param($Name, $Done, $Total) Update-AACProgress -Id 'read' -Increment 1 -Description "Read the $Name ($Done of $Total queries)" }
        $subscriptionNames = @{}
        foreach ($row in @($batch.Rows['subscriptions'])) { $subscriptionNames[([string]$row['subscriptionId']).ToLowerInvariant()] = [string]$row['name'] }

        $accounts = @(foreach ($row in @($batch.Rows['accounts'])) {
                if ($StorageAccountName -and -not (& $matchesAny ([string]$row['name']) $StorageAccountName)) { continue }
                $subscription = ([string]$row['subscriptionId']).ToLowerInvariant()
                [ordered]@{
                    Id = [string]$row['id']; Name = [string]$row['name']; ResourceGroup = [string]$row['resourceGroup']
                    SubscriptionId = $subscription; SubscriptionName = $(if ($subscriptionNames[$subscription]) { $subscriptionNames[$subscription] } else { $subscription })
                    Location = [string]$row['location']; Kind = [string]$row['kind']; Sku = [string]$row['sku']
                    BlobEndpoint = ([string]$row['blob']).TrimEnd('/'); Hns = [string]$row['hns'] -eq 'True'
                    SharedKey = [string]$row['sharedKey'] -ne 'False'
                    Firewall = $(if ([string]$row['publicNetwork'] -eq 'Disabled') { 'Public access disabled' } elseif ([string]$row['defaultAction'] -eq 'Deny') { 'Selected networks' } else { 'All networks' })
                    Containers = 0; Error = ''; Note = ''
                }
            })
        if ($StorageAccountName) {
            $missing = @($StorageAccountName | Where-Object { $pattern = $_; -not @($accounts | Where-Object { $_.Name -like $pattern }).Count })
            if ($missing.Count -eq $StorageAccountName.Count) { throw "No storage account named $(($missing | ForEach-Object { "'$_'" }) -join ', ') was found$(if ($SubscriptionId -or $ResourceGroupName) { ' in that scope' } else { ' in any subscription you can see' })." }
            foreach ($item in $missing) { Write-Warning "No storage account named '$item' was found; it's left out." }
        }
        foreach ($account in $accounts) { if (-not $account.BlobEndpoint) { $account.Note = 'No blob service (a file shares only account).' } }
        $withBlob = @($accounts | Where-Object { $_.BlobEndpoint })
        Update-AACProgress -Id 'read' -Complete -Description ('Found {0:N0} storage account(s) with a blob service in {1:N0} subscription(s)' -f $withBlob.Count, @($withBlob.SubscriptionId | Select-Object -Unique).Count)

        # --- Their containers (Resource Manager, Reader is enough) --------------------------------------
        $containers = [System.Collections.Generic.List[object]]::new()
        if ($withBlob.Count) {
            Update-AACProgress -Id 'containers' -Total $withBlob.Count -Description 'Listing the containers'
            $uris = @{}
            foreach ($account in $withBlob) { $uris[$account.Id] = "$($account.Id)/blobServices/default/containers?api-version=2023-05-01&`$maxpagesize=5000" }
            $listed = Invoke-AACArmParallel -Uri @($uris.Values) -OnProgress { param($Done, $Total) Update-AACProgress -Id 'containers' -Total $Total -Increment 1 }
            foreach ($account in $withBlob) {
                $result = $listed[$uris[$account.Id]]
                if (-not $result -or $result.Error) {
                    $account.Error = "The containers couldn't be listed: $(if ($result) { $result.Error } else { 'no response' })"
                    continue
                }
                foreach ($item in @($result.Items | Where-Object { $_ })) {
                    $name = [string]$item['name']
                    if ($ContainerName -and -not (& $matchesAny $name $ContainerName)) { continue }
                    $p = $item['properties']
                    if ($p -isnot [System.Collections.IDictionary]) { $p = @{} }
                    if ([string]$p['deleted'] -eq 'True') { continue }
                    $account.Containers++
                    $containers.Add(@{
                            Key = "$($account.Id)/$name".ToLowerInvariant(); Account = $account; Container = $name; StorageAccount = $account.Name
                            Url = "$($account.BlobEndpoint)/$name"; Sas = ''
                            PublicAccess = $(if ($p['publicAccess']) { [string]$p['publicAccess'] } else { 'None' })
                            AuthMode = ''; Tally = $null; Error = ''
                        })
                }
            }
            Update-AACProgress -Id 'containers' -Complete -Description ('Listed {0:N0} container(s) in {1:N0} storage account(s)' -f $containers.Count, $withBlob.Count)
        }

        # --- Their blobs (the blob service) -------------------------------------------------------------
        $running = @{ Blobs = [long]0; Bytes = [long]0; Done = 0 }
        $describe = { param([string] $Verb, [int] $Of) '{0} blobs: {1:N0} blob(s), {2} - {3:N0} of {4:N0} container(s)' -f $Verb, $running.Blobs, (Format-AACByteSize -Bytes $running.Bytes), $running.Done, $Of }
        $readWith = {
            param([object[]] $Items, [string] $Id, [string] $Verb, [string] $Mode)
            $running.Done = 0
            Update-AACProgress -Id $Id -Total $Items.Count -Description (& $describe $Verb $Items.Count)
            $read = Read-AACBlobContainer -Container $Items -Include $include -Top $Top -KeepBlob:$keepBlob -ThrottleLimit $ThrottleLimit -OnPage {
                param($Key, $Blobs, $Bytes)
                $running.Blobs += $Blobs
                $running.Bytes += $Bytes
                Update-AACProgress -Id $Id -Description (& $describe $Verb $Items.Count)
            } -OnDone {
                param($Key, $Failure, $Done, $Total)
                $running.Done = $Done
                Update-AACProgress -Id $Id -Increment 1 -Description (& $describe $Verb $Items.Count)
            }
            foreach ($item in $Items) {
                $outcome = $read[$item.Key]
                $item.Tally = $outcome.Tally
                $item.Error = $outcome.Error
                $item.AuthMode = $Mode
            }
        }

        $useSas = [System.Collections.Generic.List[object]]::new()
        if ($AuthMode -ne 'AccountSas' -and $containers.Count) {
            # The token for Azure Storage, once: without it every container
            # would fail the same way, after its retries.
            $tokenError = ''
            try { $null = Get-AACAccessToken -Resource 'https://storage.azure.com' }
            catch { $tokenError = $_.Exception.Message }
            if ($tokenError -and $AuthMode -eq 'EntraId') { throw $tokenError }
            if ($tokenError) {
                Write-Warning "No Entra ID token for Azure Storage ($tokenError); every account is read with an account SAS."
                foreach ($item in $containers) { $useSas.Add($item) }
            }
            else {
                & $readWith @($containers) 'blobs' 'Listing' 'Entra ID'
                if ($AuthMode -eq 'Auto') {
                    foreach ($item in $containers) { if ($item.Error -match '^(AuthorizationPermissionMismatch|KeyBasedAuthenticationNotPermitted)\b' -and $item.Tally.Pages -eq 0) { $useSas.Add($item) } }
                }
                Update-AACProgress -Id 'blobs' -Complete -Description ('Listed {0:N0} blob(s), {1}, in {2:N0} container(s) with Entra ID{3}' -f $running.Blobs, (Format-AACByteSize -Bytes $running.Bytes), ($containers.Count - $useSas.Count), $(if ($useSas.Count) { " ($($useSas.Count) need an account SAS)" }))
            }
        }
        elseif ($containers.Count) {
            foreach ($item in $containers) { $useSas.Add($item) }
        }

        if ($useSas.Count) {
            # A read-and-list SAS for each account, from listAccountSas - kept
            # in memory for this read only.
            # (By ID: Select-Object -Unique would take every dictionary for the same.)
            $unique = [ordered]@{}
            foreach ($item in $useSas) { $unique[$item.Account.Id] = $item.Account }
            $sasAccounts = @($unique.Values)
            $blocked = @($sasAccounts | Where-Object { -not $_.SharedKey })
            $sas = @{}
            $now = [datetime]::UtcNow
            $body = @{
                signedServices = 'b'; signedResourceTypes = 'co'; signedPermission = 'rl'; signedProtocol = 'https'
                signedStart = $now.AddMinutes(-15).ToString('yyyy-MM-ddTHH:mm:ssZ', [cultureinfo]::InvariantCulture)
                signedExpiry = $now.AddHours(4).ToString('yyyy-MM-ddTHH:mm:ssZ', [cultureinfo]::InvariantCulture)
                keyToSign = 'key1'
            } | ConvertTo-Json -Compress
            $requests = @($sasAccounts | Where-Object { $_.SharedKey } | ForEach-Object { @{ Key = $_.Id; Uri = "$($_.Id)/listAccountSas?api-version=2023-05-01"; Body = $body } })
            Update-AACProgress -Id 'sas' -Total ([Math]::Max(1, $requests.Count)) -Description 'Getting account SAS tokens'
            $sasErrors = if ($requests.Count) {
                Invoke-AACHttpBatch -Request $requests -ThrottleLimit 8 -OnResponse {
                    param($Key, [string] $Content)
                    $sas[$Key] = [string](ConvertFrom-Json -InputObject $Content -AsHashtable)['accountSasToken']
                    $null
                } -OnDone { param($Key, $Failure, $Done, $Total) Update-AACProgress -Id 'sas' -Increment 1 }
            }
            else { @{} }
            Update-AACProgress -Id 'sas' -Complete -Description ('Got an account SAS for {0:N0} of {1:N0} storage account(s)' -f $sas.Count, $sasAccounts.Count)

            $readable = [System.Collections.Generic.List[object]]::new()
            foreach ($item in $useSas) {
                $id = $item.Account.Id
                if ($sas[$id]) { $item.Sas = $sas[$id]; $readable.Add($item); continue }
                $item.AuthMode = 'Account SAS'
                $item.Error = if ($item.Account -in $blocked) { 'KeyBasedAuthenticationNotPermitted: the account doesn''t allow shared key access, so no account SAS can be made.' } else { "No account SAS: $($sasErrors[$id])" }
            }
            if ($readable.Count) {
                $running.Blobs = 0; $running.Bytes = 0
                & $readWith @($readable) 'sas-blobs' 'Listing (account SAS)' 'Account SAS'
                Update-AACProgress -Id 'sas-blobs' -Complete -Description ('Listed {0:N0} blob(s), {1}, in {2:N0} container(s) with an account SAS' -f $running.Blobs, (Format-AACByteSize -Bytes $running.Bytes), $readable.Count)
            }
            foreach ($item in $useSas) { $item.Sas = '' }
        }
        $clock.Stop()

        # --- The rows -----------------------------------------------------------------------------------
        $rows = [System.Collections.Generic.List[object]]::new()
        foreach ($item in $containers) {
            $rows.Add((ConvertTo-AACStorageContainerRow -Item $item))
        }
        foreach ($account in $withBlob | Where-Object { $_.Error }) {
            $rows.Add((ConvertTo-AACStorageContainerRow -Item @{ Account = $account; Container = $null; Url = $account.BlobEndpoint; PublicAccess = ''; AuthMode = ''; Tally = $null; Error = $account.Error }))
        }
        $sorted = @($rows | Sort-Object -Property SubscriptionName, StorageAccount, @{ Expression = 'Size'; Descending = $true }, Container)
        $report = ConvertTo-AACStorageSizeReport -Row $sorted -Account $accounts -Elapsed $clock.Elapsed

        $scope = [ordered]@{
            Scope = if ($SubscriptionId) { "subscription(s) $($SubscriptionId -join ', ')" } else { 'every subscription the account can see' }
        }
        if ($ResourceGroupName) { $scope['Resource groups'] = $ResourceGroupName -join ', ' }
        if ($StorageAccountName) { $scope['Storage accounts'] = $StorageAccountName -join ', ' }
        if ($ContainerName) { $scope['Containers'] = $ContainerName -join ', ' }
        $scope['Read with'] = @{ EntraId = 'Entra ID'; AccountSas = 'an account SAS'; Auto = 'Entra ID, else an account SAS' }[$AuthMode]
        if ($include.Count) { $scope['Also listed'] = $include -join ', ' }

        $csvRows = @($sorted | Select-Object -Property * -ExcludeProperty LargestBlobs, Blobs)
        $blobRows = @(if ($blobCsvFullPath) { $sorted | ForEach-Object { $_.Blobs } | Select-Object -Property StorageAccount, Container, Name, Size, SizeText, AccessTier, BlobType, Kind, LastModified, Snapshot, VersionId })
        if ($csvFullPath) {
            $null = Invoke-AACExport -CsvPath $csvFullPath -CsvObject $csvRows -Noun 'container'
        }
        if ($blobCsvFullPath) {
            $null = Invoke-AACExport -CsvPath $blobCsvFullPath -CsvObject $blobRows -Noun 'blob'
        }
        if ($htmlFullPath) {
            $null = Invoke-AACExport -HtmlPath $htmlFullPath -WriteHtml {
                Write-AACStorageSizeHtml -Report $report -Path $htmlFullPath -Title $Title -Detail $scope
            }
        }
        @{ Report = $report; Scope = $scope }
    }

    if ($showView) {
        Invoke-AACPagedOutput -NoPaging:$NoPaging -ScriptBlock {
            Show-AACStorageSizeView -Report $state.Report -Scope $state.Scope
        }
    }
    if ($returnObjects) {
        $state.Report.Rows
    }
}
