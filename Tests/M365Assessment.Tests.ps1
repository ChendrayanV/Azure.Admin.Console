<#
    Unit tests for Invoke-AACM365Assessment: the Microsoft Graph calls and
    the permissions they need, the Graph reader (pages, singletons,
    refusals), the assessment of a made-up Contoso tenant
    (Fixtures\ContosoM365.ps1) - Entra ID, Microsoft 365, Intune and the
    zero-trust findings - and the command with Graph mocked: the object, the
    view, the CSV files and the tabbed HTML report.
#>

BeforeDiscovery {
    $modulePath = Resolve-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '..')
    if (-not (Get-Module -Name 'Azure.Admin.Console')) {
        Import-Module -Name (Join-Path -Path $modulePath -ChildPath 'Azure.Admin.Console.psd1') -ErrorAction Stop
    }
}

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Fixtures/ContosoM365.ps1')
    $script:f = Get-AACContosoM365
    $script:assess = {
        param([hashtable] $Data = $script:f.Data, [hashtable] $Errors = @{})
        InModuleScope 'Azure.Admin.Console' -Parameters @{ D = $Data; E = $Errors; N = $script:f.Now; R = $script:f.Resolved } {
            param($D, $E, $N, $R)
            ConvertTo-AACM365Assessment -Data $D -Errors $E -Query (Get-AACM365AssessmentQuery) -Now $N -Resolved $R
        }
    }
    $script:a = & $script:assess
    $script:findings = { param([string] $Area, $From = $script:a) @($From.Findings | Where-Object Area -EQ $Area | ForEach-Object { "$($_.Severity) $($_.Finding)" } | Sort-Object) }
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
}

Describe 'Azure Admin Console - what the Microsoft 365 assessment reads' {
    It 'reads Entra ID, Microsoft 365 and Intune from Microsoft Graph, each call with the permission it needs' {
        $q = InModuleScope 'Azure.Admin.Console' { Get-AACM365AssessmentQuery }
        $q.Count | Should -Be 46
        foreach ($name in $q.Keys) {
            $q[$name].Uri | Should -Match '^https://graph\.microsoft\.com/(v1\.0|beta)/' -Because "$name is a Graph call"
            $q[$name].Permission | Should -Match '^[A-Za-z]+\.Read(\.[A-Za-z]+)?\.?[A-Za-z]*$' -Because "$name needs only a read permission"
        }
        @($q.Values | Where-Object { $_.Uri -like '*/beta/*' } | ForEach-Object { $_.Data }) | Should -Match 'beta' -Because 'only Intune''s endpoint security uses the beta API'
        @((InModuleScope 'Azure.Admin.Console' { Get-AACM365AssessmentQuery -Section Intune }).Values.Section | Select-Object -Unique) | Should -Be @('Intune')
    }

    It 'lists the permissions to sign in with, as Connect-AAC scopes' {
        $scopes = @(Invoke-AACM365Assessment -ListPermission)
        $scopes | Should -Contain 'https://graph.microsoft.com/Policy.Read.All'
        $scopes | Should -Contain 'https://graph.microsoft.com/DeviceManagementManagedDevices.Read.All'
        $scopes | Should -Contain 'https://graph.microsoft.com/IdentityProvider.Read.All'
        @($scopes | Where-Object { $_ -match 'Write' }).Count | Should -Be 0
        @(Invoke-AACM365Assessment -ListPermission -Section Entra) | Should -Not -Contain 'https://graph.microsoft.com/Device.Read.All'
    }

    It 'reads in rounds: legacy sign-ins per protocol, Graph''s grants after its service principal, and only the users the checks need' {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Read-AACGraphQuery -MockWith {
            $data = @{}; $errors = @{}
            foreach ($name in $Query.Keys) {
                $uri = [System.Uri]::UnescapeDataString([string]$(if ($Query[$name] -is [System.Collections.IDictionary]) { $Query[$name].Uri } else { $Query[$name] }))
                switch -Wildcard ($name) {
                    'RoleAssignments' { $data[$name] = @(0..19 | ForEach-Object { @{ principalId = "u$_"; roleDefinitionId = 'r' } }); break }
                    'ConditionalAccess' { $data[$name] = @(@{ conditions = @{ users = @{ includeUsers = @('All'); excludeUsers = @('bg1', 'u3') } } }, @{ conditions = $null }); break }
                    'Users|*' {
                        # Graph refuses the last sign-in (no Entra ID P1); without it, the users come.
                        if ($uri -match 'signInActivity') { $errors[$name] = 'Neither tenant is B2C or tenant doesn''t have premium license' }
                        elseif ($name -eq 'Users|names') { $data[$name] = @(@{ id = 'bg1'; displayName = 'Break glass' }) }
                        else { $data[$name] = @(@{ id = 'u3' }, @{ id = 'bg1'; displayName = 'Break glass' }) }
                        break
                    }
                    'GraphServicePrincipal' { $data[$name] = @{ id = 'graph-sp' }; break }
                    'GraphAppRoleGrants' { $data[$name] = @(@{ principalId = 'x' }); break }
                    'LegacySignIns|IMAP4' { $data[$name] = @(@{ clientAppUsed = 'IMAP4' }); break }
                    default { $data[$name] = @() }
                }
            }
            @{ Data = $data; Errors = $errors }
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Resolve-AACHostName -MockWith { @{} }
        $script:progress = [System.Collections.Generic.List[string]]::new()
        $read = InModuleScope 'Azure.Admin.Console' -Parameters @{ Log = $script:progress } {
            param($Log)
            Read-AACM365Graph -Query (Get-AACM365AssessmentQuery -Section Entra, Microsoft365) -Now ([datetime]::new(2026, 10, 7, 0, 0, 0, [System.DateTimeKind]::Utc)) -OnProgress {
                param($Batch, $What, $Done, $Total, $Waiting, $Finished)
                if ($Finished) { $Log.Add("done $Batch") } elseif (-not $What) { $Log.Add("start $Batch") }
            }.GetNewClosure()
        }
        # A batch at a time, in order, each finished before the next starts.
        @($script:progress | Select-Object -Unique) | Should -Be @(
            'start Entra ID: tenant and policies'; 'done Entra ID: tenant and policies'
            'start Entra ID: admin roles, MFA and users'; 'done Entra ID: admin roles, MFA and users'
            'start Sign-in and audit logs'; 'done Sign-in and audit logs'
            'start Threat protection'; 'done Threat protection'
            'start Applications'; 'done Applications'
            'start Microsoft 365'; 'done Microsoft 365'
        )
        # The latest audit event and Secure Score: one item, not every page of their history.
        Should -Invoke -ModuleName 'Azure.Admin.Console' Read-AACGraphQuery -ParameterFilter { $Query.Contains('DirectoryAudits') -and $Query['DirectoryAudits'].MaxItems -eq 1 } -Times 1 -Exactly
        Should -Invoke -ModuleName 'Azure.Admin.Console' Read-AACGraphQuery -ParameterFilter { $Query.Contains('SecureScore') -and $Query['SecureScore'].MaxItems -eq 1 } -Times 1 -Exactly
        @($read.Data['Users'] | ForEach-Object { $_['id'] } | Sort-Object) | Should -Be @('bg1', 'u3') -Because 'the batches overlap; each user is kept once'
        $read.Fallbacks | Should -Be @('Users')
        $read.Errors.Contains('Users') | Should -BeFalse
        @($read.Data['LegacySignIns']).Count | Should -Be 1
        @($read.Data['GraphAppRoleGrants']).Count | Should -Be 1
        # After its service principal, Graph's grants; after the roles and policies, the users by ID (21: the 20 principals and one excluded) - 15 to a query - and by name.
        Should -Invoke -ModuleName 'Azure.Admin.Console' Read-AACGraphQuery -Times 1 -Exactly -ParameterFilter { @($Query.Keys) -join ',' -eq 'GraphAppRoleGrants' -and $Query['GraphAppRoleGrants'] -like '*/servicePrincipals/graph-sp/appRoleAssignedTo*' }
        Should -Invoke -ModuleName 'Azure.Admin.Console' Read-AACGraphQuery -Times 1 -Exactly -ParameterFilter {
            @($Query.Keys | Where-Object { $_ -like 'Users|*' } | Sort-Object) -join ',' -eq 'Users|ids0,Users|ids15,Users|names' -and
            [System.Uri]::UnescapeDataString($Query['Users|ids15']) -like "*id in ('u15','u16','u17','u18','u19','bg1')*" -and
            [System.Uri]::UnescapeDataString($Query['Users|names']) -like "*startswith(displayName,'break')*" -and $Query['Users|ids0'] -match 'signInActivity'
        }
        # Round three: the same lookups, without the last sign-in.
        Should -Invoke -ModuleName 'Azure.Admin.Console' Read-AACGraphQuery -Times 1 -Exactly -ParameterFilter { @($Query.Keys).Count -eq 3 -and @($Query.Values | Where-Object { $_ -match 'signInActivity' }).Count -eq 0 -and $Query.Contains('Users|names') }
        Should -Invoke -ModuleName 'Azure.Admin.Console' Read-AACGraphQuery -Times 1 -Exactly -ParameterFilter { @($Query.Keys | Where-Object { $_ -like 'LegacySignIns|*' }).Count -eq 10 -and [System.Uri]::UnescapeDataString([string]$Query['LegacySignIns|IMAP4'].Uri) -like "*createdDateTime ge 2026-09-30T00:00:00Z and clientAppUsed eq 'IMAP4'*" -and -not $Query.Contains('Users') }
    }

    It 'reads lists to the last page, keeps singletons as objects, and carries on past a refusal' {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Invoke-AACHttpBatch -MockWith {
            $failures = @{}
            foreach ($r in $Request) {
                switch ($r.Key) {
                    'list' { $null = & $OnResponse 'list' '{"value":[{"id":"a"}],"@odata.nextLink":"https://graph.microsoft.com/v1.0/next"}'; $null = & $OnResponse 'list' '{"value":[{"id":"b"}]}'; $failures['list'] = '' }
                    'single' { $null = & $OnResponse 'single' '{"id":"policy","isEnabled":true}'; $failures['single'] = '' }
                    'capped' {
                        # MaxItems 1: the next page is not asked for (Graph gives a nextLink even with $top=1).
                        $script:cappedNext = & $OnResponse 'capped' '{"value":[{"id":"latest"}],"@odata.nextLink":"https://graph.microsoft.com/v1.0/older"}'
                        $failures['capped'] = ''
                    }
                    'refused' { $failures['refused'] = 'Insufficient privileges to complete the operation.' }
                }
                if ($OnDone) { & $OnDone $r.Key $failures[$r.Key] 1 3 }
            }
            $failures
        }
        $read = InModuleScope 'Azure.Admin.Console' { Read-AACGraphQuery -Query ([ordered]@{ list = 'https://graph.microsoft.com/v1.0/list'; single = 'https://graph.microsoft.com/v1.0/single'; refused = 'https://graph.microsoft.com/v1.0/refused'; capped = @{ Uri = 'https://graph.microsoft.com/v1.0/capped'; MaxItems = 1 } }) }
        @($read.Data['list'] | ForEach-Object { $_['id'] }) | Should -Be @('a', 'b')
        $read.Data['single']['isEnabled'] | Should -BeTrue
        $read.Data.Contains('refused') | Should -BeFalse
        $read.Errors['refused'] | Should -Match 'Insufficient privileges'
        @($read.Data['capped'] | ForEach-Object { $_['id'] }) | Should -Be @('latest')
        $script:cappedNext | Should -BeNullOrEmpty -Because 'with MaxItems reached, the next page is not read'
        Should -Invoke -ModuleName 'Azure.Admin.Console' Invoke-AACHttpBatch -ParameterFilter { $Resource -eq 'https://graph.microsoft.com' } -Times 1 -Exactly -Because 'one Graph token for every call'
    }
}

Describe 'Azure Admin Console - the Microsoft 365 assessment' {
    It 'flags Entra ID: MFA, legacy authentication, risk policies, admins, emergency access, consent, users and guest settings' {
        & $script:findings 'Entra ID' | Should -Be (@(
                'High Administrators without MFA registered'
                'High Applications are Global Administrators'
                'High Guests hold admin roles'
                'High Legacy authentication is in use'
                'High Legacy authentication is not blocked'
                'High Users can consent to any app'
                'Low Conditional Access policies left in report-only'
                'Low Global Administrators with other admin roles'
                'Low No phishing-resistant method (FIDO2 passkeys) is on'
                'Low No technical contact'
                'Low Only one emergency access account'
                'Low Phishable methods are on'
                'Medium Admin accounts synced from on-premises'
                'Medium Admin roles assigned to deleted or unknown principals'
                'Medium Administrators without phishing-resistant MFA'
                'Medium Admins who don''t sign in'
                'Medium Anyone, guests included, can invite guests'
                'Medium Directory sync has stopped'
                'Medium Disabled accounts still hold admin roles'
                'Medium Emergency access account without a passkey'
                'Medium Every user can register applications'
                'Medium No risk-based Conditional Access'
                'Medium Standing privileged access'
                'Medium Users without MFA registered'
                'Medium Exclusions from the MFA policy'
                'High Global Administrator activates without MFA'
                'Medium Global Administrator activates without approval'
                'Medium Privileged roles activate without MFA'
                'Low Long role activations'
                'Low Permanent Global Administrator assignments are allowed'
                'Low Password hash sync is off'
                'Low Accidental deletion prevention is off'
                'Medium Large groups excluded from Conditional Access'
                'Medium Dynamic groups excluded from Conditional Access'
                'High Guests get admin roles through groups'
                'Low Guest access isn''t reviewed'
                'Medium Admin roles aren''t reviewed'
            ) | Sort-Object)
    }

    It 'measures MFA coverage - registered and phishing-resistant - by members, admins and guests' {
        @($script:a.MfaCoverage | ForEach-Object { "$($_.Scope) $($_.Users) $($_.MfaPercent)% $($_.PhishingResistant)" }) | Should -Be @('Members 6 50% 0', 'Administrators 3 67% 0', 'Guests 1 0% 0')
        ($script:a.Settings | Where-Object Setting -EQ 'MFA required by Conditional Access for').Value | Should -Be 'All users - 1 user(s) and 1 group(s) excluded'
    }

    It 'reads the PIM role settings of the privileged roles' {
        @($script:a.PimRoleSettings | ForEach-Object { "$($_.Role)|$($_.MfaOnActivation)|$($_.Approval)|$($_.MaxActivationHours)|$($_.PermanentActive)" }) | Should -Be @(
            'Global Administrator|No|No|10|Allowed'
            'Security Administrator|No|Yes|4|No'
            'User Administrator|Yes|No|8|No'
        ) -Because 'Global Reader is not privileged, so it is left out'
    }

    It 'opens up the groups excluded from Conditional Access and the groups holding roles' {
        $g = $script:a.GroupExposure
        @($g | ForEach-Object { "$($_.Group)|$($_.Members)|$($_.Guests)|$($_.Dynamic)|$($_.Why)" }) | Should -Be @(
            'Helpdesk|2|1|No|Holds: User Administrator (active)'
            'Travelling staff|7|0|Yes|Excluded from: Require MFA for all users'
        )
    }

    It 'flags threat protection: risky users, risk detections and Defender XDR incidents' {
        & $script:findings 'Threat protection' | Should -Be (@(
                'High High-risk users not remediated'
                'High High-severity incidents open'
                'High Users confirmed compromised'
                'Medium High-risk detections'
                'Medium Incidents open for over a week with no owner'
                'Medium Users at risk'
            ) | Sort-Object)
        @($script:a.RiskyUsers.UserPrincipalName) | Should -Be @('zoe@contoso.com', 'dave@contoso.com', 'erin@contoso.com') -Because 'remediated users are left out; compromised ones come first'
        @($script:a.RiskDetections | ForEach-Object { "$($_.Detection) $($_.Detections) $($_.High)" }) | Should -Be @('Leaked Credentials 2 2', 'Unfamiliar Features 3 0')
        $script:a.Incidents[0].Active | Should -Be 'Yes'
    }

    It 'lists the licensed users with no activity, app protection, and access reviews' {
        @($script:a.InactiveUsers.UserPrincipalName) | Should -Be @('erin@contoso.com')
        @($script:a.AppProtection | ForEach-Object { "$($_.Platform)|$($_.Assigned)|$($_.SendDataTo)|$($_.PinRequired)" }) | Should -Be @('iOS/iPadOS|Yes|All Apps|No')
        $script:a.AccessReviews[0].Covers | Should -Be 'Groups'
    }

    It 'shows in one place what was assessed, what wasn''t and why, and what Graph doesn''t reach' {
        $c = $script:a.Coverage
        @($c | Where-Object Status -EQ 'Assessed').Count | Should -Be 34 -Because 'every lens was read'
        @($c | Where-Object Status -EQ 'Not covered').Lens | Should -Contain 'Whether unified audit logging is actually on'
        ($c | Where-Object Area -EQ 'Exchange Online').ToCover | Should -Match 'Exchange Online admin API'
        $partial = & $script:assess (@{} + $script:f.Data | ForEach-Object { $d = $_.Clone(); $d.Remove('PimPolicies'); $d.Remove('Groups'); $d }) @{ PimPolicies = 'The tenant needs an AAD Premium 2 license.'; Groups = 'Insufficient privileges to complete the operation.' }
        $pim = $partial.Coverage | Where-Object Lens -EQ 'PIM role settings'
        "$($pim.Status) | $($pim.Reads)" | Should -Be 'Not assessed | 0 of 1'
        $pim.ToCover | Should -Match 'RoleManagementPolicy\.Read\.Directory.*licence'
        ($partial.Coverage | Where-Object Lens -EQ 'Groups behind exclusions and roles').Status | Should -Be 'Partly assessed'
        $partial.Coverage[0].Status | Should -Be 'Not assessed' -Because 'what wasn''t assessed comes first'
    }

    It 'finds the emergency access accounts - excluded from every policy, or by name - and checks them' {
        $e = @($script:a.EmergencyAccess)
        $e.Count | Should -Be 1
        "$($e[0].Account) | $($e[0].DetectedBy) | $($e[0].GlobalAdministrator) | $($e[0].CloudOnly) | $($e[0].PhishingResistant) | $($e[0].ExcludedFromPolicies)" | Should -Be 'BG Admin 1 | Excluded from every enabled Conditional Access policy; name | Yes | Yes | No | 2 of 2'
        @($script:a.PrivilegedAccounts | Where-Object PrincipalId -EQ 'u-bg1').Issues | Should -Be '' -Because 'an emergency account that doesn''t sign in is as it should be'
        $none = $script:f.Data.Clone()
        $none.ConditionalAccess = @(); $none.Users = @($script:f.Data.Users | Where-Object id -NE 'u-bg1'); $none.Registration = @($script:f.Data.Registration | Where-Object id -NE 'u-bg1')
        & $script:findings 'Entra ID' (& $script:assess $none) | Should -Contain 'Medium No emergency access account found'
    }

    It 'lists the privileged accounts: dangling ones and overlapping roles first' {
        $p = $script:a.PrivilegedAccounts
        $issues = @{}; foreach ($row in $p) { $issues[$row.PrincipalId] = $row.Issues }
        $issues['u-bob'] | Should -Be 'No recent sign-in, Synced from on-premises'
        $issues['u-zoe'] | Should -Be 'Disabled, No recent sign-in'
        $issues['u-gary'] | Should -Be 'Guest'
        $issues['u-ghost'] | Should -Be 'Deleted or unknown'
        $issues['sp-automation'] | Should -Be 'Application'
        ($p | Where-Object PrincipalId -EQ 'u-alice').OverlapDetail | Should -Be 'Global Administrator plus other roles'
        ($p | Where-Object PrincipalId -EQ 'u-alice').Roles | Should -Be 'Global Administrator, Exchange Administrator'
        $p[0].Dangling | Should -Be 'Yes'
        $script:a.Stats.DanglingAdmins | Should -Be 5
    }

    It 'doesn''t flag MFA when a policy requires it of everyone, and does when none does' {
        & $script:findings 'Entra ID' | Should -Not -Contain 'High MFA is not required of everyone'
        $data = $script:f.Data.Clone()
        $data.ConditionalAccess = @($script:f.Data.ConditionalAccess | Select-Object -Skip 1)
        & $script:findings 'Entra ID' (& $script:assess $data) | Should -Contain 'High MFA is not required of everyone'
        $data.SecurityDefaults = @{ isEnabled = $true }
        & $script:findings 'Entra ID' (& $script:assess $data) | Should -Not -Contain 'High MFA is not required of everyone' -Because 'security defaults require MFA'
    }

    It 'describes the Conditional Access policies' {
        $p = $script:a.ConditionalAccess
        @($p.State) | Should -Be @('On', 'On', 'Report-only')
        $mfa = $p | Where-Object Policy -EQ 'Require MFA for all users'
        "$($mfa.Users) | $($mfa.Excluded) | $($mfa.Applications) | $($mfa.Grant) | $($mfa.RequiresMfa)" | Should -Be 'All users | 2 | All cloud apps | Mfa | Yes' -Because 'a break-glass account and the travel group are excluded'
        ($p | Where-Object Policy -Like 'Admins*').Grant | Should -Be 'Strength: Phishing-resistant MFA'
        ($p | Where-Object Policy -Like 'Block*').ClientApps | Should -Be 'Exchange Active Sync, Other'
        $p[0].PSObject.Properties.Name | Should -Not -Contain '_On' -Because 'the analysis flags are dropped'
        $p[0].PSObject.TypeNames[0] | Should -Be 'AAC.M365ConditionalAccessPolicy'
    }

    It 'lists admin roles - active and eligible - privileged first, with each admin''s MFA registration' {
        $r = $script:a.RoleAssignments
        @($r | Where-Object GlobalAdministrator -EQ 'Yes' | ForEach-Object { "$($_.Principal) $($_.Assignment) $($_.MfaRegistered)" }) | Should -Be @('Alice Active Yes', 'Automation runbook Active n/a', 'BG Admin 1 Active Yes', 'Bob Active No', 'Carol Eligible Yes') -Because 'an eligible assignment is named from the active ones'
        ($r | Where-Object Role -EQ 'Global Reader').Privileged | Should -Be 'No'
        $script:a.Stats.GlobalAdmins | Should -Be 5
    }

    It 'counts MFA registration over members, admins without it first' {
        $script:a.Stats.MfaRegistered | Should -Be 50 -Because '3 of 6 members; the guest is left out'
        $script:a.Registration[0].User | Should -Be 'Bob'
        $script:a.Stats.AdminsWithoutMfa | Should -Be 1
    }

    It 'flags Microsoft 365: Secure Score, audit log search, sharing and domains' {
        & $script:findings 'Microsoft 365' | Should -Be (@(
                'High Anyone links are allowed'
                'High Audit log search is off'
                'Info Federated domains'
                'Low Sharing open to every domain'
                'Low Unverified domains'
                'Medium Guests can reshare'
                'Medium Secure Score under 50%'
                'Low Licensed users with no activity in 30 days'
            ) | Sort-Object)
        $script:a.Stats.SecureScore | Should -Be 40
        $script:a.Stats.AuditLog | Should -Be 'Off'
    }

    It 'lists the Secure Score controls by gap, with how to fix them, and leaves deprecated ones out' {
        $c = $script:a.SecureScoreControls
        @($c.Control) | Should -Be @('Turn on audit log search', 'Ensure all users can complete MFA')
        "$($c[0].Status) $($c[0].Gap) $($c[0].Remediation) $($c[0].Description)" | Should -Be 'To do 10 Turn it on. Audit is off.'
        $c[1].Status | Should -Be 'Partly'
    }

    It 'flags applications: over-privileged permissions, expiring and long-lived credentials, dangling redirect URIs' {
        & $script:findings 'Applications' | Should -Be (@(
                'Critical App can take over the tenant'
                'High Apps with tenant-wide access to data'
                'High Dangling redirect URIs on Azure hosts'
                'High Tenant-wide consent to high-risk delegated permissions'
                'High Unverified publishers with high-risk permissions'
                'High Wildcard redirect URIs'
                'Low Expired credentials left on apps'
                'Low Localhost redirect URIs on multi-tenant apps'
                'Low Long-lived certificates'
                'Medium App credentials expiring within 30 days'
                'Medium Long-lived client secrets'
                'Medium Redirect URIs to hosts that don''t resolve'
                'Medium Redirect URIs without HTTPS'
            ) | Sort-Object)
        ($script:a.Findings | Where-Object Finding -EQ 'App can take over the tenant').Item | Should -Be 'Automation runbook'
        @($script:a.Findings | Where-Object { $_.Detail -like '*Microsoft Teams*' }).Count | Should -Be 0 -Because 'Microsoft''s own apps are not flagged'
    }

    It 'rates each app permission, and tells Microsoft''s apps, your own and third parties apart' {
        $p = $script:a.AppPermissions
        @($p | Where-Object App -EQ 'MailSync Pro' | ForEach-Object { "$($_.Permission)|$($_.Kind)|$($_.Risk)|$($_.Owner)|$($_.Verified)" } | Sort-Object) | Should -Be @('Mail.Read|Application|High|Third party|No', 'Mail.ReadWrite|Delegated (all users)|High|Third party|No', 'offline_access|Delegated (all users)|Info|Third party|No')
        ($p | Where-Object { $_.App -eq 'Payroll' -and $_.Permission -eq 'User.Read' }).Kind | Should -Be 'Delegated (2 users)' -Because 'one consent per user, added up'
        ($p | Where-Object App -EQ 'Microsoft Teams').Owner | Should -Be 'Microsoft'
        $p[0].Risk | Should -Be 'Critical'
    }

    It 'lists app credentials by status, and leaves Microsoft''s own out' {
        @($script:a.AppCredentials | ForEach-Object { "$($_.App)|$($_.Type)|$($_.Status)" }) | Should -Be @('Payroll|Secret|Expiring', 'Partner portal|Secret|Expired', 'Payroll|Secret|Long-lived', 'Payroll|Certificate|Long-lived')
        ($script:a.AppCredentials | Where-Object Status -EQ 'Expiring').DaysLeft | Should -Be 20
    }

    It 'checks every redirect URI, its host looked up in DNS' {
        $u = @($script:a.RedirectUris | Where-Object Status -EQ 'Issue')
        @($u | ForEach-Object { "$($_.Severity)|$($_.Issue)|$($_.Uri)" }) | Should -Be @(
            'High|Wildcard|https://*.contoso.com/cb'
            'High|Dangling: the Azure host no longer exists|https://payroll-old.azurewebsites.net/signin'
            'Medium|Dangling: the host doesn''t resolve|https://gone.fabrikam-old.com/auth'
            'Medium|Not HTTPS|http://intranet.contoso.com/cb'
            'Low|Localhost on a multi-tenant app|http://localhost:8080'
        )
        ($script:a.RedirectUris | Where-Object Uri -EQ 'https://app.contoso.com').Resolves | Should -Be 'Yes'
    }

    It 'counts the legacy authentication sign-ins by protocol' {
        @($script:a.LegacyAuthentication | ForEach-Object { "$($_.Protocol) $($_.Successful)/$($_.Failed) $($_.TopUsers)" }) | Should -Be @('IMAP4 3/0 dave@contoso.com (3)', 'Authenticated SMTP 1/0 printer@contoso.com (1)', 'POP3 0/1 erin@contoso.com (1)')
        $script:a.Stats.LegacySignIns | Should -Be 4
    }

    It 'reads the user consent settings and the admin consent workflow' {
        ($script:a.Settings | Where-Object Setting -EQ 'User consent to apps').Value | Should -Be 'Any app, any permission (legacy)'
        ($script:a.Settings | Where-Object Setting -EQ 'Group owner consent').Value | Should -Be 'microsoft-dynamically-managed-permissions-for-team'
        ($script:a.Settings | Where-Object Setting -EQ 'Admin consent requests').Value | Should -Be 'Off'
        $low = $script:f.Data.Clone()
        $low.AuthorizationPolicy = $script:f.Data.AuthorizationPolicy.Clone(); $low.AuthorizationPolicy.defaultUserRolePermissions = @{ permissionGrantPoliciesAssigned = @('ManagePermissionGrantsForSelf.microsoft-user-default-low') }
        $findings = & $script:findings 'Entra ID' (& $script:assess $low)
        $findings | Should -Not -Contain 'High Users can consent to any app'
        $findings | Should -Contain 'Low Admin consent requests are off'
    }

    It 'flags security defaults left on where Conditional Access is licensed' {
        $on = $script:f.Data.Clone(); $on.SecurityDefaults = @{ isEnabled = $true }
        & $script:findings 'Entra ID' (& $script:assess $on) | Should -Contain 'Low Security defaults instead of Conditional Access'
    }

    It 'flags Intune: compliance, stale, unencrypted and rooted devices, enrollment, endpoint security and unmanaged devices' {
        & $script:findings 'Intune' | Should -Be (@(
                'High Jailbroken or rooted devices'
                'High Non-compliant devices'
                'Low Compliance policies not assigned'
                'Low High device enrollment limit'
                'Low Personal devices can enroll'
                'Low Stale Entra ID devices'
                'Medium Devices with no compliance policy are marked compliant'
                'Medium No attack surface reduction policy'
                'Medium No endpoint detection and response policy'
                'Medium No firewall policy'
                'Medium Stale managed devices'
                'Medium Unencrypted computers'
                'Medium Unmanaged devices in use'
                'Medium No app protection for Android'
                'Medium App protection lets data leave managed apps'
                'Low App protection without a PIN'
            ) | Sort-Object)
    }

    It 'reads endpoint security from settings catalog policies and template intents, and nothing else' {
        @($script:a.EndpointSecurity | ForEach-Object { "$($_.Family): $($_.Policy) ($($_.Assigned))" }) | Should -Be @('Antivirus: Defender Antivirus (Yes)', 'Disk encryption: BitLocker (Yes)', 'Firewall: Firewall draft (No)')
    }

    It 'lists enrollment restrictions per platform, and the devices - Intune''s and Entra ID''s' {
        @($script:a.EnrollmentRestrictions | ForEach-Object { "$($_.Type)|$($_.Platform)|$($_.PersonalBlocked)|$($_.Limit)" }) | Should -Be @('Device limit|||15', 'Platform restrictions|iOS/iPadOS|Yes|', 'Platform restrictions|Windows|No|', 'Windows Hello For Business|||')
        $script:a.ManagedDevices[0].Compliance | Should -Be 'Noncompliant'
        ($script:a.ManagedDevices | Where-Object Device -EQ 'PC2').Stale | Should -Be 'Yes'
        $script:a.EntraDevices[0].Device | Should -Be 'LAPTOP-HOME' -Because 'unmanaged devices in use come first'
        ($script:a.EntraDevices | Where-Object Device -EQ 'PC1').Join | Should -Be 'Entra joined'
    }

    It 'copes with a near-empty tenant, and with one of everything (no list may become a lone object or nothing)' {
        # Each collection empty, then each cut to its first item: PowerShell
        # unrolls a script block's output, so @() and one-item lists are where
        # .Count on nothing breaks under strict mode.
        $empty = @{}; $single = @{}
        foreach ($key in $script:f.Data.Keys) {
            $value = $script:f.Data[$key]
            $empty[$key] = if ($value -is [System.Collections.IDictionary]) { @{} } else { @() }
            $single[$key] = if ($value -is [System.Collections.IDictionary]) { $value } else { @($value | Select-Object -First 1) }
        }
        { & $script:assess $empty } | Should -Not -Throw
        { & $script:assess $single } | Should -Not -Throw
        $one = & $script:assess $single
        @($one.PrivilegedAccounts).Count | Should -Be 2 -Because 'one active and one eligible assignment'
        # And the Entra section alone, Users and Conditional Access refused, as a tenant without Entra ID P1 might.
        $entra = @{}; foreach ($key in (InModuleScope 'Azure.Admin.Console' { Get-AACM365AssessmentQuery -Section Entra }).Keys) { if ($key -notin 'Users', 'ConditionalAccess', 'Registration', 'LegacySignIns' -and $script:f.Data.Contains($key)) { $entra[$key] = $script:f.Data[$key] } }
        { & $script:assess $entra @{ Users = 'Forbidden'; ConditionalAccess = 'Forbidden'; Registration = 'Forbidden'; LegacySignIns = 'Forbidden' } } | Should -Not -Throw
    }

    It 'says what it couldn''t read, with the permission each read needs - and still assesses the rest' {
        $data = $script:f.Data.Clone(); $data.Remove('ConditionalAccess'); $data.Remove('ManagedDevices')
        $partial = & $script:assess $data @{ ConditionalAccess = 'Insufficient privileges'; ManagedDevices = 'Forbidden' }
        $missing = @($partial.Permissions | Where-Object Status -EQ 'Not read')
        @($missing | ForEach-Object { "$($_.Data): $($_.Permission)" }) | Should -Be @('Conditional Access policies: Policy.Read.All', 'Intune managed devices: DeviceManagementManagedDevices.Read.All')
        $partial.Notices | Should -Match 'Policy\.Read\.All'
        & $script:findings 'Entra ID' $partial | Should -Not -Contain 'High Legacy authentication is not blocked' -Because 'nothing is guessed from what wasn''t read'
        @($partial.ManagedDevices).Count | Should -Be 0
        @($partial.Domains).Count | Should -Be 4
    }
}

Describe 'Azure Admin Console - Invoke-AACM365Assessment' {
    BeforeEach {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Read-AACGraphQuery -MockWith {
            $data = @{}; $errors = @{}
            foreach ($name in $Query.Keys) {
                $base = $name -replace '\|.*$', ''
                if ($script:refuse -contains $base) { $errors[$name] = 'Insufficient privileges to complete the operation.' }
                elseif ($name -like 'LegacySignIns|*') { $protocol = $name.Split('|')[1]; $data[$name] = @($script:f.Data.LegacySignIns | Where-Object { $_.clientAppUsed -eq $protocol }) }
                elseif ($name -like 'GroupMembers|*') { $groupId = $name.Split('|')[1]; $data[$name] = @($script:f.Data.GroupMembers | Where-Object { $_._groupId -eq $groupId }) }
                elseif ($name -like '*|*' -and $script:f.Data.Contains($base)) { $data[$name] = $script:f.Data[$base] }
                elseif ($script:f.Data.Contains($name)) { $data[$name] = $script:f.Data[$name] }
                if ($OnDone) { & $OnDone $name '' 1 $Query.Count }
            }
            @{ Data = $data; Errors = $errors }
        }
        $script:refuse = @()
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Resolve-AACHostName -MockWith { $script:f.Resolved }
        InModuleScope 'Azure.Admin.Console' { $script:AACSession = [pscustomobject]@{ Account = 'admin@contoso.com'; TenantId = 't'; AccessToken = 'x'; ExpiresOn = (Get-Date).AddHours(1); RefreshToken = 'r'; ClientId = 'c'; Scope = @('s') } }
    }
    AfterEach { InModuleScope 'Azure.Admin.Console' { $script:AACSession = $null } }

    It 'returns the assessment as one object with every table, from one Graph token' {
        $result = Invoke-AACM365Assessment -NoDisplay
        $result.PSObject.TypeNames[0] | Should -Be 'AAC.M365Assessment'
        $result.Tenant | Should -Be 'Contoso'
        @($result.ConditionalAccess).Count | Should -Be 3
        @($result.ManagedDevices).Count | Should -Be 4
        Should -Invoke -ModuleName 'Azure.Admin.Console' Get-AACAccessToken -ParameterFilter { $Resource -eq 'https://graph.microsoft.com' }
    }

    It 'reads only the sections asked for' {
        $result = Invoke-AACM365Assessment -Section Intune -NoDisplay
        @($result.ConditionalAccess).Count | Should -Be 0
        @($result.Permissions.Area | Select-Object -Unique) | Should -Be @('Intune')
    }

    It 'stops with what to do when Graph refuses everything' {
        $script:refuse = @(InModuleScope 'Azure.Admin.Console' { (Get-AACM365AssessmentQuery).Keys })
        { Invoke-AACM365Assessment -NoDisplay } | Should -Throw '*refused every read*'
    }

    It 'shows the view at the prompt, with what couldn''t be read' {
        $script:refuse = @('SecureScore')
        $text = (& $script:capture { Invoke-AACM365Assessment -NoPaging }).Text
        $text | Should -Match 'Conditional Access'
        $text | Should -Match 'Require MFA for all users'
        $text | Should -Match 'Administrators without MFA registered'
        $text | Should -Match 'SecurityEvents\.Read\.All'
    }

    It 'writes a CSV per table and the tabbed HTML report' {
        $csv = Join-Path $TestDrive 'm365'
        $html = Join-Path $TestDrive 'm365.html'
        $null = & $script:capture { Invoke-AACM365Assessment -CsvPath $csv -HtmlPath $html }
        @(Get-ChildItem -LiteralPath $csv -Filter '*.csv').Name | Should -Contain 'm365-conditional-access.csv'
        @(Get-ChildItem -LiteralPath $csv -Filter '*.csv').Count | Should -Be 33
        $page = Get-Content -LiteralPath $html -Raw
        foreach ($tab in 'Findings', 'Entra ID', 'Microsoft 365', 'Applications', 'Threat protection', 'Intune', 'Coverage') { $page | Should -Match ([regex]::Escape("`"name`":`"$tab`"")) }
        $page | Should -Match 'Require MFA for all users'
    }
}

Describe 'Azure Admin Console - Invoke-AACM365Assessment through the real Graph reader' {
    BeforeEach {
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Get-AACAccessToken -MockWith { 'fake-token' }
        InModuleScope 'Azure.Admin.Console' { $script:AACSession = [pscustomobject]@{ Account = 'admin@contoso.com'; TenantId = 't'; AccessToken = 'x'; ExpiresOn = (Get-Date).AddHours(1); RefreshToken = 'r'; ClientId = 'c'; Scope = @('s') } }
    }
    AfterEach { InModuleScope 'Azure.Admin.Console' { $script:AACSession = $null } }

    It 'runs end to end through the real Graph reader - its callbacks inside the HTTP batch, as against Graph' {
        # Only the HTTP layer is faked: the reader and the command's progress
        # callbacks run inside Invoke-AACHttpBatch, whose own variables
        # ($Request, $OnDone...) once hid theirs.
        # (A mock of Invoke-AACHttpBatch itself runs in the test's scope, where
        # its variables hide nothing: only the HTTP send is faked.)
        $script:keyOf = @{}
        $queries = InModuleScope 'Azure.Admin.Console' { Get-AACM365AssessmentQuery }
        foreach ($name in $queries.Keys) { $script:keyOf[$queries[$name].Uri] = $name }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Send-AACHttpRequest -MockWith {
            $decoded = [System.Uri]::UnescapeDataString($Uri)
            $value = if ($decoded -match "clientAppUsed eq '([^']+)'") { $protocol = $Matches[1]; @($script:f.Data.LegacySignIns | Where-Object { $_.clientAppUsed -eq $protocol }) }
            elseif ($decoded -like '*/servicePrincipals/sp-graph/appRoleAssignedTo*') { $script:f.Data.GraphAppRoleGrants }
            elseif ($decoded -match '/groups/([^/]+)/transitiveMembers') { $groupId = $Matches[1]; @($script:f.Data.GroupMembers | Where-Object { $_._groupId -eq $groupId }) }
            elseif ($decoded -like '*/v1.0/groups?$filter=*') { $script:f.Data.Groups }
            elseif ($decoded -like '*/identityProtection/riskDetections*') { $script:f.Data.RiskDetections }
            elseif ($decoded -like '*/v1.0/users?$filter=*') { $script:f.Data.Users }
            else { $script:f.Data[$script:keyOf[$Uri]] }
            $body = if ($value -is [System.Collections.IDictionary]) { $value } else { @{ value = @($value) } }
            $response = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::OK)
            $response.Content = [System.Net.Http.StringContent]::new((ConvertTo-Json -InputObject $body -Depth 20 -Compress))
            [System.Threading.Tasks.Task]::FromResult($response)
        }
        Mock -ModuleName 'Azure.Admin.Console' -CommandName Resolve-AACHostName -MockWith { $script:f.Resolved }
        $result = InModuleScope 'Azure.Admin.Console' { Invoke-AACM365Assessment -NoDisplay }
        $result.Tenant | Should -Be 'Contoso'
        @($result.ConditionalAccess).Count | Should -Be 3
        $result.SecureScore | Should -Be 40
        @($result.Permissions | Where-Object Status -EQ 'Read').Count | Should -Be 46
        @($result.Coverage | Where-Object Status -EQ 'Assessed').Count | Should -Be 34
        @($result.LegacyAuthentication).Count | Should -Be 3 -Because 'one query per legacy protocol, merged'
        @($result.AppPermissions | Where-Object Risk -EQ 'Critical').App | Should -Be 'Automation runbook' -Because 'the second round read the Graph grants'
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Send-AACHttpRequest -Times 57 -Exactly -Because 'per batch: 12; 5, then users by ID and name and groups by ID, then 2 groups'' members; 10 protocols and the audit log; 3; 4 and the Graph grants; 5; 11 - every one through the real reader and HTTP batch'
        Should -Invoke -ModuleName 'Azure.Admin.Console' -CommandName Resolve-AACHostName -ParameterFilter { @($HostName) -contains 'payroll-old.azurewebsites.net' -and @($HostName) -notcontains 'localhost' }
    }

}
