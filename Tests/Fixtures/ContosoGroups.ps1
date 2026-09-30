<#
    Made-up Contoso Entra ID groups as Microsoft Graph returns them, for
    GroupMembership.Tests.ps1:

      grp-finance (Security, cloud)       Ada (member), Gus (guest), grp-finance-emea
        grp-finance-emea (synced from AD)  Grace (disabled), Ada, app-payroll (service principal)
      grp-all-staff (Microsoft 365, dynamic)  Ada, Linus
      grp-loop-a                           grp-loop-b
        grp-loop-b                         Linus, grp-loop-a   (a loop)
      grp-empty                            no members

    $script:graphFake answers Send-AACHttpRequest like Graph: group filters
    (exact name, startswith), and members in pages of two (@odata.nextLink).
#>
function Get-AACContosoGroups {
    $user = { param($Id, $Name, $Upn, $Type = 'Member', $Enabled = $true, $Dept = 'Finance') @{ '@odata.type' = '#microsoft.graph.user'; id = $Id; displayName = $Name; userPrincipalName = $Upn; mail = $Upn; userType = $Type; accountEnabled = $Enabled; jobTitle = 'Analyst'; department = $Dept } }
    $group = { param($Id, $Name, $Types = @(), $Security = $true, $Mail = $false, $Synced = $null) @{ '@odata.type' = '#microsoft.graph.group'; id = $Id; displayName = $Name; groupTypes = $Types; securityEnabled = $Security; mailEnabled = $Mail; isAssignableToRole = $false; onPremisesSyncEnabled = $Synced; description = "$Name description"; membershipRule = $(if ($Types -contains 'DynamicMembership') { 'user.department -ne null' }); mail = $null } }
    $ada = & $user 'u-ada' 'Ada Lovelace' 'ada@contoso.example'
    $gus = & $user 'u-gus' 'Gus Guest' 'gus_fabrikam.example#EXT#@contoso.example' 'Guest'
    $grace = & $user 'u-grace' 'Grace Hopper' 'grace@contoso.example' 'Member' $false
    $linus = & $user 'u-linus' 'Linus Torvalds' 'linus@contoso.example' 'Member' $true 'IT'
    $payroll = @{ '@odata.type' = '#microsoft.graph.servicePrincipal'; id = 'sp-payroll'; displayName = 'app-payroll' }
    $groups = @{
        'g-fin'   = & $group 'g-fin' 'grp-finance'
        'g-emea'  = & $group 'g-emea' 'grp-finance-emea' @() $true $false $true
        'g-all'   = & $group 'g-all' 'grp-all-staff' @('Unified', 'DynamicMembership') $false $true
        'g-loopa' = & $group 'g-loopa' 'grp-loop-a'
        'g-loopb' = & $group 'g-loopb' 'grp-loop-b'
        'g-empty' = & $group 'g-empty' 'grp-empty'
    }
    @{
        Groups  = $groups
        Members = @{
            'g-fin'   = @($ada, $gus, $groups['g-emea'])
            'g-emea'  = @($grace, $ada, $payroll)
            'g-all'   = @($ada, $linus)
            'g-loopa' = @($groups['g-loopb'])
            'g-loopb' = @($linus, $groups['g-loopa'])
            'g-empty' = @()
        }
    }
}

$script:graphFake = {
    param([string] $Uri)
    $data = $script:contosoGroups
    $respond = {
        param($Status, $Body)
        $response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]$Status)
        $response.Content = [System.Net.Http.StringContent]::new(($Body | ConvertTo-Json -Depth 10 -Compress))
        [System.Threading.Tasks.Task]::FromResult($response)
    }
    $decoded = [System.Uri]::UnescapeDataString($Uri)
    if ($decoded -match '/groups/([^/?]+)/members') {
        $id = $Matches[1]
        if ($script:graphDeny -contains $id) { return & $respond 403 @{ error = @{ code = 'Authorization_RequestDenied'; message = 'Insufficient privileges to complete the operation.' } } }
        $all = @($data.Members[$id])
        $skip = if ($decoded -match 'skip=(\d+)') { [int]$Matches[1] } else { 0 }
        $page = @($all | Select-Object -Skip $skip -First 2)
        $body = @{ value = $page }
        if ($skip + 2 -lt $all.Count) { $body['@odata.nextLink'] = "https://graph.microsoft.com/v1.0/groups/$id/members?skip=$($skip + 2)" }
        return & $respond 200 $body
    }
    $groups = @($data.Groups.Values)
    if ($decoded -match "displayName eq '((?:[^']|'')*)'") { $name = $Matches[1] -replace "''", "'"; $groups = @($groups | Where-Object { $_.displayName -eq $name }) }
    elseif ($decoded -match "startswith\(displayName,'((?:[^']|'')*)'\)") { $prefix = $Matches[1] -replace "''", "'"; $groups = @($groups | Where-Object { $_.displayName.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase) }) }
    & $respond 200 @{ value = $groups }
}
