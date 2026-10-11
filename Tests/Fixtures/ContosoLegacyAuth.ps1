<#
    Made-up resources and tenant answers for LegacyAuthentication.Tests.ps1 (and
    the demo), as Get-AACLegacyAuthenticationQuery's Resource Graph and
    Microsoft Graph queries return them:

      Azure     st-keys (shared keys, TLS 1.0), sql1 (SQL logins), cosmos1 and
                batch1 (local auth), la1 (workspace keys), acr1 (admin user),
                redis1 (non-TLS port, access keys), aks-noentra, aks-local,
                vm-linux (passwords), kv1 (access policies), app1 (SCM basic
                auth); st-good, sb1 and vm-win are fine; app2's policies
                couldn't be read
      Entra ID  IMAP sign-ins (2 successful), failed POP sign-ins, a report-only
                block policy, security defaults off, an implicit-grant app, a
                public client app, two apps with only secrets, SMS enabled;
                'Other clients' sign-ins couldn't be read (no P1)
#>
function Get-AACContosoLegacyAuth {
    $sub = '11111111-1111-1111-1111-111111111111'
    $row = {
        param([string] $Type, [string] $Name, [hashtable] $Extra = @{})
        $r = @{ id = "/subscriptions/$sub/resourcegroups/rg-app/providers/$Type/$Name"; name = $Name; type = $Type; resourceGroup = 'rg-app'; subscriptionId = $sub; location = 'westeurope' }
        foreach ($k in $Extra.Keys) { $r[$k] = $Extra[$k] }
        $r
    }
    $read = @{
        Errors = @{}
        Rows   = @{
            storage    = @((& $row 'microsoft.storage/storageaccounts' 'st-keys' @{ sharedKey = ''; tls = 'TLS1_0' }), (& $row 'microsoft.storage/storageaccounts' 'st-good' @{ sharedKey = 'False'; tls = 'TLS1_2' }))
            sql        = @((& $row 'microsoft.sql/servers' 'sql1' @{ entraOnly = 'False'; tls = '1.2' }))
            postgres   = @()
            localAuth  = @(
                (& $row 'microsoft.documentdb/databaseaccounts' 'cosmos1' @{ disabled = '' })
                (& $row 'microsoft.servicebus/namespaces' 'sb1' @{ disabled = 'True' })
                (& $row 'microsoft.operationalinsights/workspaces' 'la1' @{ disabled = '' })
                (& $row 'microsoft.batch/batchaccounts' 'batch1' @{ disabled = ''; modes = @('SharedKey', 'AAD') })
            )
            registries = @((& $row 'microsoft.containerregistry/registries' 'acr1' @{ admin = 'True' }))
            redis      = @((& $row 'microsoft.cache/redis' 'redis1' @{ nonSsl = 'True'; keysOff = ''; tls = '1.2' }))
            aks        = @((& $row 'microsoft.containerservice/managedclusters' 'aks-noentra' @{ entra = 'False'; localOff = '' }), (& $row 'microsoft.containerservice/managedclusters' 'aks-local' @{ entra = 'True'; localOff = 'False' }))
            vms        = @((& $row 'microsoft.compute/virtualmachines' 'vm-linux' @{ linux = 'True'; passwordOff = 'False' }), (& $row 'microsoft.compute/virtualmachines' 'vm-win' @{ linux = 'False'; passwordOff = '' }))
            keyVaults  = @((& $row 'microsoft.keyvault/vaults' 'kv1' @{ rbac = 'False' }))
            sites      = @((& $row 'microsoft.web/sites' 'app1' @{ kind = 'app' }), (& $row 'microsoft.web/sites' 'app2' @{ kind = 'app' }))
        }
    }
    $app1 = $read.Rows.sites[0].id
    $app2 = $read.Rows.sites[1].id
    $signIn = { param([string] $User, [int] $Code) @{ userPrincipalName = $User; clientAppUsed = 'x'; status = @{ errorCode = $Code }; createdDateTime = '2026-10-10T10:00:00Z' } }

    @{
        Sub        = $sub
        Names      = @{ $sub = 'sub-prod' }
        Read       = $read
        App1       = $app1
        App2       = $app2
        Publishing = @{ $app1 = @{ Ftp = $false; Scm = $true }; $app2 = $null }
        Entra      = @{
            Errors = @{ 'signIns|Other clients' = 'Forbidden: the tenant needs Entra ID P1' }
            Data   = @{
                'signIns|IMAP4'               = @((& $signIn 'alice@contoso.com' 0), (& $signIn 'alice@contoso.com' 0), (& $signIn 'bob@contoso.com' 50126))
                'signIns|POP3'                = @((& $signIn 'carol@contoso.com' 50126), (& $signIn 'dave@contoso.com' 50053))
                'signIns|Exchange ActiveSync' = @()
                conditionalAccess             = @(@{ displayName = 'Block legacy auth'; state = 'enabledForReportingButNotEnforced'; conditions = @{ clientAppTypes = @('exchangeActiveSync', 'other'); users = @{ includeUsers = @('All') } }; grantControls = @{ builtInControls = @('block') } })
                securityDefaults              = @{ isEnabled = $false }
                applications                  = @(
                    @{ displayName = 'app-implicit'; appId = 'a1'; web = @{ implicitGrantSettings = @{ enableAccessTokenIssuance = $true } }; passwordCredentials = @(@{ keyId = 'k' }); keyCredentials = @() }
                    @{ displayName = 'app-ropc'; appId = 'a2'; isFallbackPublicClient = $true; passwordCredentials = @(@{ keyId = 'k' }); keyCredentials = @(@{ keyId = 'c' }) }
                    @{ displayName = 'app-secret'; appId = 'a3'; passwordCredentials = @(@{ keyId = 'k' }); keyCredentials = @() }
                )
                authMethods                   = @{ authenticationMethodConfigurations = @(@{ id = 'Sms'; state = 'enabled' }, @{ id = 'Voice'; state = 'disabled' }) }
            }
        }
    }
}
