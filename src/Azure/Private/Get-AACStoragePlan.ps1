function Get-AACStoragePlan {
    <#
    .SYNOPSIS
        Reads what exists for a storage account's desired state and works out
        every change - the plan of Deploy-AACStorageAccount.
    .DESCRIPTION
        1. The account (GET). When it exists, everything else it should have
           (GET, -ThrottleLimit at a time) and - for the services the
           configuration names - the containers, file shares, queues and
           tables it already has.
        2. Role assignments: each role name or ID resolved to its definition;
           an assignment that already exists at that scope for that
           principal and role is kept, whatever its name. A new one gets a
           name derived from scope, principal and role - like Bicep's guid()
           - so running again finds it rather than adding another.
        3. Blobs: when the container exists, the blob's Content-MD5 (HEAD)
           against the local file's, so an unchanged file isn't uploaded
           again.
        4. Each node compared (Compare-AACResourceState). Containers, shares,
           queues and tables that exist but aren't in the configuration are
           Delete with -Prune, else Drift (reported, untouched).

        Returns AAC.StorageChange objects in apply order: Order, Action
        (Create, Update, NoChange, Replace, Delete, Drift, Unknown), Kind,
        Resource, Differences, Method, Uri, Body, Id, Type, Name, Parent,
        Planned (the resource as it will be - for the policy check and
        PSRule), Exists, Reason, Source / ContentMD5 for blobs.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [object[]] $Node,

        [Parameter(Mandatory)]
        [string] $SubscriptionId,

        [switch] $Prune,

        [ValidateRange(1, 32)]
        [int] $ThrottleLimit = 12
    )

    $uri = { param([string] $Id, [string] $ApiVersion) "$Id`?api-version=$ApiVersion" }
    $changes = [System.Collections.Generic.List[object]]::new()
    $change = {
        param([System.Collections.IDictionary] $N, [string] $Action, [object[]] $Differences, [string] $Method, $Body, $Planned, [string] $Reason = '', [hashtable] $Extra = @{})
        $row = [ordered]@{
            PSTypeName  = 'AAC.StorageChange'
            Order       = $N['Order']
            Action      = $Action
            Kind        = $N['Kind']
            Resource    = $N['Label']
            Differences = @($Differences)
            Reason      = $Reason
            Method      = $Method
            Uri         = $(if ($N['ApiVersion']) { & $uri $N['Id'] $N['ApiVersion'] } else { $N['Id'] })
            Body        = $Body
            Id          = $N['Id']
            Type        = [string]$N['Type']
            Name        = [string]$N['Name']
            Parent      = [string]$N['Parent']
            Planned     = $Planned
            Exists      = $Action -notin 'Create'
        }
        foreach ($key in $Extra.Keys) { $row[$key] = $Extra[$key] }
        $changes.Add([pscustomobject]$row)
    }
    $accountNode = @($Node | Where-Object Kind -EQ 'account')[0]
    $accountRead = Invoke-AACArmParallel -Uri @(& $uri $accountNode.Id $accountNode.ApiVersion) -ThrottleLimit 1
    $accountResult = $accountRead[(& $uri $accountNode.Id $accountNode.ApiVersion)]
    if ($accountResult.Status -notin 200, 404) { throw "The storage account couldn't be read ($($accountResult.Status)): $($accountResult.Error)" }
    $accountExists = $accountResult.Status -eq 200

    # --- 1. Everything else that should exist ------------------------------------------------------------------
    $current = @{ ($accountNode.Id) = $(if ($accountExists) { $accountResult.Body }) }
    $armNodes = @($Node | Where-Object { $_.Kind -notin 'account', 'roleAssignment', 'blob' })
    $listUris = @{}
    if ($accountExists) {
        foreach ($n in $Node | Where-Object Kind -In 'blobService', 'fileService', 'queueService', 'tableService') {
            $child = @{ blobService = 'containers'; fileService = 'shares'; queueService = 'queues'; tableService = 'tables' }[$n.Kind]
            $listUris[$n.Kind] = & $uri "$($n.Id)/$child" $n.ApiVersion
        }
        $reads = Invoke-AACArmParallel -Uri (@($armNodes | ForEach-Object { & $uri $_.Id $_.ApiVersion }) + @($listUris.Values)) -ThrottleLimit $ThrottleLimit
        foreach ($n in $armNodes) {
            $result = $reads[(& $uri $n.Id $n.ApiVersion)]
            if ($result.Status -eq 200) { $current[$n.Id] = $result.Body }
            elseif ($result.Status -ne 404) { $current[$n.Id] = @{ AACError = "$($result.Status): $($result.Error)" } }
        }
    }

    # --- 2. Role assignments ---------------------------------------------------------------------------------------
    $roleNodes = @($Node | Where-Object Kind -EQ 'roleAssignment')
    $roleIds = @{}
    foreach ($role in @($roleNodes | ForEach-Object { $_['Role'] } | Select-Object -Unique)) {
        $roleIds[$role] = if ($role -match '^/subscriptions/.+/roleDefinitions/[0-9a-fA-F-]{36}$' -or $role -match '^/providers/Microsoft\.Authorization/roleDefinitions/[0-9a-fA-F-]{36}$') { $role }
        elseif ($role -match '^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$') { "/subscriptions/$SubscriptionId/providers/Microsoft.Authorization/roleDefinitions/$role" }
        else {
            $found = @((Invoke-AACArmRequest -Uri "/subscriptions/$SubscriptionId/providers/Microsoft.Authorization/roleDefinitions?api-version=2022-04-01&`$filter=$([uri]::EscapeDataString("roleName eq '$($role -replace "'", "''")'"))")['value'])
            if (-not $found.Count) { throw "No role named '$role' was found." }
            "/subscriptions/$SubscriptionId/providers/Microsoft.Authorization/roleDefinitions/$($found[0]['name'])"
        }
    }
    $existingAssignments = @{}
    if ($accountExists -and $roleNodes.Count) {
        $scopes = @($roleNodes | ForEach-Object { $_['Scope'] } | Select-Object -Unique)
        $lists = Invoke-AACArmParallel -Uri @($scopes | ForEach-Object { "$_/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01&`$filter=atScope()" }) -ThrottleLimit $ThrottleLimit
        foreach ($scope in $scopes) {
            $result = $lists["$scope/providers/Microsoft.Authorization/roleAssignments?api-version=2022-04-01&`$filter=atScope()"]
            $existingAssignments[$scope] = @(if ($result.Status -eq 200) { @($(if ($null -ne $result.Items) { $result.Items } else { $result.Body['value'] })) | Where-Object { ([string]$_['properties']['scope']).TrimEnd('/') -ieq $scope.TrimEnd('/') } })
        }
    }
    $guid = {
        param([string] $Text)
        $hash = [System.Security.Cryptography.MD5]::HashData([System.Text.Encoding]::UTF8.GetBytes($Text.ToLowerInvariant()))
        ([guid]::new($hash)).ToString()
    }

    # --- 3 and 4. Compare ----------------------------------------------------------------------------------------------
    foreach ($n in $Node) {
        switch ($n.Kind) {
            'roleAssignment' {
                $assignment = $n.Assignment
                $roleId = $roleIds[$n.Role]
                $principal = [string]$assignment['principalId']
                if (-not $principal) { throw "Role assignment '$($n.Role)' needs a principalId." }
                $roleGuid = ($roleId -split '/')[-1]
                $existing = @(@($existingAssignments[$n.Scope]) | Where-Object { $null -ne $_ -and [string]$_['properties']['principalId'] -ieq $principal -and ([string]$_['properties']['roleDefinitionId'] -split '/')[-1] -ieq $roleGuid }) | Select-AACFirst 1
                $assignmentName = if ($assignment['name']) { [string]$assignment['name'] } else { & $guid "$($n.Scope)|$principal|$roleGuid" }
                $id = if ($existing) { [string]$existing['id'] } else { "$($n.Scope)/providers/Microsoft.Authorization/roleAssignments/$assignmentName" }
                $properties = [ordered]@{ roleDefinitionId = $roleId; principalId = $principal }
                foreach ($key in 'principalType', 'description', 'condition', 'conditionVersion') { if ($assignment[$key]) { $properties[$key] = [string]$assignment[$key] } }
                $n.Id = $id
                $n.Name = ($id -split '/')[-1]
                $body = [ordered]@{ properties = $properties }
                $differences = @([pscustomobject]@{ Property = 'role'; Current = ''; Desired = $n.Role; Immutable = $false }, [pscustomobject]@{ Property = 'principal'; Current = ''; Desired = "$principal$(if ($properties.Contains('principalType')) { " ($($properties.principalType))" })"; Immutable = $false })
                if ($existing) { & $change $n 'NoChange' @() '' $null $existing }
                else { & $change $n 'Create' $differences 'Put' $body ([ordered]@{ id = $id; name = $n.Name; type = $n.Type; properties = $properties }) }
            }
            'blob' {
                $info = Get-Item -LiteralPath $n.Source -ErrorAction SilentlyContinue
                if (-not $info -or $info.PSIsContainer) { throw "Blob $($n.BlobName): no file at '$($n.Source)'." }
                if ($info.Length -gt 256MB) { throw "Blob $($n.BlobName): '$($n.Source)' is $([Math]::Round($info.Length / 1MB)) MB; this command uploads files up to 256 MB in one request. Use AzCopy for larger files." }
                $md5 = [Convert]::ToBase64String([System.Security.Cryptography.MD5]::HashData([System.IO.File]::ReadAllBytes($info.FullName)))
                $containerExists = $accountExists -and $current.Contains($n.Parent) -and $current[$n.Parent] -and -not $current[$n.Parent].Contains('AACError')
                $extra = @{ Source = $info.FullName; ContentMD5 = $md5; Length = $info.Length; ContentType = $(if ($n.ContentType) { $n.ContentType } else { 'application/octet-stream' }) }
                if (-not $containerExists) { & $change $n 'Create' @([pscustomobject]@{ Property = 'content'; Current = ''; Desired = "$($info.Name) ($('{0:N0}' -f $info.Length) bytes)"; Immutable = $false }) 'Upload' $null $null '' $extra; continue }
                try {
                    $head = Invoke-AACHttp -Method Head -Uri $n.Id -Resource 'https://storage.azure.com' -Header @{ 'x-ms-version' = '2023-11-03' } -MaxAttempts 3
                    $remote = if ($head.Headers.ContainsKey('Content-MD5')) { [string]$head.Headers['Content-MD5'] } else { '' }
                    if ($remote -eq $md5) { & $change $n 'NoChange' @() '' $null $null '' $extra }
                    else { & $change $n 'Update' @([pscustomobject]@{ Property = 'content (MD5)'; Current = $(if ($remote) { $remote } else { 'no MD5' }); Desired = $md5; Immutable = $false }) 'Upload' $null $null '' $extra }
                }
                catch {
                    if ($_.Exception.Data['StatusCode'] -eq 404) { & $change $n 'Create' @([pscustomobject]@{ Property = 'content'; Current = ''; Desired = "$($info.Name) ($('{0:N0}' -f $info.Length) bytes)"; Immutable = $false }) 'Upload' $null $null '' $extra }
                    else { & $change $n 'Unknown' @() '' $null $null "The blob couldn't be read: $($_.Exception.Message) (Storage Blob Data Reader or Contributor and network access to the account are needed)." $extra }
                }
            }
            default {
                $now = if ($n.Kind -eq 'account') { $current[$n.Id] } elseif ($current.Contains($n.Id)) { $current[$n.Id] } else { $null }
                if ($now -is [System.Collections.IDictionary] -and $now.Contains('AACError')) { & $change $n 'Unknown' @() '' $null $null "It couldn't be read: $($now['AACError'])"; continue }
                $result = Compare-AACResourceState -Node $n -Current $now
                $planned = if ($now) { Merge-AACObject -Base $now -Overlay $n.Desired } else { $n.Desired }
                $planned = Merge-AACObject -Base $planned -Overlay ([ordered]@{ id = $n.Id; name = $(if ($n.Name) { ($n.Name -split '/')[-1] } else { '' }); type = $n.Type })
                $reason = if ($result.Action -eq 'Replace') { "Azure can't change $(@($result.Differences | Where-Object Immutable | ForEach-Object { $_.Property }) -join ', ') in place." } else { '' }
                & $change $n $result.Action $result.Differences $result.Method $result.Body $planned $reason
            }
        }
    }

    # --- Containers, shares, queues and tables not in the configuration -------------------------------------------------
    foreach ($kind in @($listUris.Keys)) {
        $result = $reads[$listUris[$kind]]
        if ($result.Status -ne 200) { continue }
        $childKind = @{ blobService = 'container'; fileService = 'share'; queueService = 'queue'; tableService = 'table' }[$kind]
        $wanted = @($Node | Where-Object Kind -EQ $childKind | ForEach-Object { ($_.Id -split '/')[-1].ToLowerInvariant() })
        $label = @{ container = 'Container'; share = 'File share'; queue = 'Queue'; table = 'Table' }[$childKind]
        foreach ($item in @($(if ($null -ne $result.Items) { $result.Items } else { $result.Body['value'] }) | Where-Object { $_ -is [System.Collections.IDictionary] })) {
            $itemName = [string]$item['name']
            if ($wanted -contains $itemName.ToLowerInvariant()) { continue }
            $orphan = @{ Kind = $childKind; Label = "$label $itemName"; Id = [string]$item['id']; ApiVersion = '2023-05-01'; Type = [string]$item['type']; Name = $itemName; Order = 2; Parent = ([string]$item['id'] -replace '/[^/]+/[^/]+$', '') }
            if ($Prune) { & $change $orphan 'Delete' @([pscustomobject]@{ Property = 'everything in it'; Current = $itemName; Desired = ''; Immutable = $false }) 'Delete' $null $null 'Not in the configuration (-Prune): it is deleted, with everything in it.' }
            else { & $change $orphan 'Drift' @() '' $null $null 'Exists, but not in the configuration: left as it is (-Prune deletes it).' }
        }
    }
    $actionOrder = @{ Delete = 1 }
    @($changes | Sort-Object -Property Order, @{ Expression = { $actionOrder[$_.Action] ?? 0 } } -Stable)
}
