function ConvertTo-AACGovernanceChange {
    <#
    .SYNOPSIS
        Builds Get-AACGovernanceChange's timeline (AAC.GovernanceChange):
        the policy and access changes of the last days - created and
        updated policy definitions, initiatives and assignments, custom
        roles and role assignments - with who made them.
    .DESCRIPTION
        No Azure calls. -Read is Invoke-AACGraphBatch's result (rows with
        kind, id, name, scope, createdOn, createdBy, updatedOn, updatedBy,
        detail fields); -Directory Get-AACDirectoryObject's for the authors
        and role assignments' principals ($null: not read). -Since is the
        start of the window; -InScope tells whether a scope is in scope.

        A row per change (created, or updated when updated after created):
        when, what changed, its name and scope, who - resolved to a name -
        and Detail (a role assignment's role and principal; an assignment's
        enforcement). Notable changes get a severity:
          Medium  a privileged role (Owner, User Access Administrator, RBAC
                  Administrator, Contributor) assigned; a custom role changed;
                  a policy assignment set to DoNotEnforce
          Info    everything else
        Returns @{ Changes (newest first); Notices; Stats }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Read,

        [hashtable] $Directory,

        [Parameter(Mandatory)]
        [datetime] $Since,

        [scriptblock] $InScope = { param([string] $Scope) $true }
    )

    $get = ${function:Get-AACMember}
    $text = { param($Object, [string] $Path) $v = & $get $Object $Path; if ($null -eq $v) { '' } else { [string]$v } }
    $rowsOf = { param([string] $Name) @(if ($Read.Rows -and $Read.Rows.Contains($Name)) { $Read.Rows[$Name] | Where-Object { $null -ne $_ } }) }
    $date = {
        param([string] $Value)
        $d = [datetime]::MinValue
        if ($Value -and [datetime]::TryParse($Value, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$d)) { $d } else { $null }
    }
    $notices = [System.Collections.Generic.List[string]]::new()
    $kinds = [ordered]@{ policyDefinitions = 'Policy definition'; policySets = 'Initiative'; policyAssignments = 'Policy assignment'; roleDefinitions = 'Custom role'; roleAssignments = 'Role assignment' }
    foreach ($key in @($Read.Errors.Keys | Sort-Object)) { $notices.Add("The $(if ($kinds.Contains($key)) { $kinds[$key].ToLowerInvariant() + ' changes' } else { $key }) couldn't be read: $($Read.Errors[$key] -replace '\s+', ' ')") }
    $entraRead = $null -ne $Directory -and -not $Directory.Error
    if ($null -ne $Directory -and $Directory.Error) { $notices.Add("The authors couldn't be looked up in Entra ID ($($Directory.Error)): they are shown by ID.") }
    $who = {
        param([string] $Id)
        if (-not $Id) { return '' }
        if ($Id -notmatch '^[0-9a-fA-F-]{36}$') { return $Id }
        if ($entraRead -and $Directory.Objects.Contains($Id.ToLowerInvariant())) { $o = $Directory.Objects[$Id.ToLowerInvariant()]; return $(if (& $text $o 'userPrincipalName') { & $text $o 'userPrincipalName' } else { & $text $o 'displayName' }) }
        if ($entraRead) { return "$Id (deleted)" }
        $Id
    }
    $scopeText = { param([string] $Scope) if (-not $Scope -or $Scope -eq '/') { 'root' } elseif ($Scope -match '/managementgroups/([^/]+)') { "management group $($Matches[1])" } elseif ($Scope -match '^/subscriptions/([^/]+)/resourcegroups/([^/]+)') { "resource group $($Matches[2])" } elseif ($Scope -match '^/subscriptions/([^/]+)') { "subscription $($Matches[1])" } else { $Scope } }
    $privileged = @('8e3af657-a8ff-443c-a75c-2fe8c4bcb635', '18d7d88d-d35e-4fb5-a5c3-7773c20a72d9', 'f58310d9-a9f6-439a-9e8d-f62e7b41a168', 'b24988ac-6180-42a0-ab88-20f7382dd24c')
    $roleName = @{}
    foreach ($row in (& $rowsOf 'roleNames')) { $roleName[((& $text $row 'id') -split '/')[-1].ToLowerInvariant()] = & $text $row 'roleName' }

    $changes = [System.Collections.Generic.List[object]]::new()
    foreach ($key in $kinds.Keys) {
        foreach ($row in (& $rowsOf $key)) {
            $scope = & $text $row 'scope'
            if (-not (& $InScope $scope)) { continue }
            $created = & $date (& $text $row 'createdOn')
            $updated = & $date (& $text $row 'updatedOn')
            $events = @()
            if ($created -and $created -ge $Since) { $events += @{ Change = 'Created'; When = $created; By = (& $text $row 'createdBy') } }
            if ($updated -and $updated -ge $Since -and (-not $created -or ($updated - $created).TotalMinutes -gt 1)) { $events += @{ Change = 'Updated'; When = $updated; By = (& $text $row 'updatedBy') } }
            foreach ($e in $events) {
                $detail = ''; $severity = 'Info'; $note = ''
                switch ($key) {
                    'roleAssignments' {
                        $guid = ((& $text $row 'roleId') -split '/')[-1].ToLowerInvariant()
                        $role = if ($roleName.Contains($guid)) { $roleName[$guid] } else { $guid }
                        $detail = "$role to $(& $who (& $text $row 'principalId')) ($(& $text $row 'principalType'))"
                        if ($privileged -contains $guid) { $severity = 'Medium'; $note = "Privileged access granted: $role." }
                    }
                    'roleDefinitions' { $severity = 'Medium'; $note = 'A custom role was created or changed: check what it now allows.' }
                    'policyAssignments' {
                        $enforcement = & $text $row 'enforcement'
                        $detail = "Enforcement: $(if ($enforcement) { $enforcement } else { 'Default' })"
                        if ($enforcement -eq 'DoNotEnforce') { $severity = 'Medium'; $note = 'The assignment does not enforce (DoNotEnforce): its deny and deploy effects are off.' }
                    }
                }
                $item = [pscustomobject][ordered]@{
                    Severity = $severity
                    When     = $e.When
                    Change   = $e.Change
                    Kind     = $kinds[$key]
                    Name     = $(if (& $text $row 'name') { & $text $row 'name' } else { ((& $text $row 'id') -split '/')[-1] })
                    Scope    = (& $scopeText $scope)
                    By       = (& $who $e.By)
                    Detail   = $detail
                    Note     = $note
                    Id       = (& $text $row 'id')
                }
                $item.PSObject.TypeNames.Insert(0, 'AAC.GovernanceChange')
                $changes.Add($item)
            }
        }
    }
    $sorted = @($changes | Sort-Object When -Descending)
    @{
        Changes = $sorted
        Notices = @($notices)
        Stats   = @{
            Changes    = $sorted.Count
            Notable    = @($sorted | Where-Object Severity -EQ 'Medium').Count
            Authors    = @($sorted | ForEach-Object { $_.By } | Where-Object { $_ } | Select-Object -Unique).Count
            Privileged = @($sorted | Where-Object { $_.Note -like 'Privileged access granted*' }).Count
        }
    }
}
