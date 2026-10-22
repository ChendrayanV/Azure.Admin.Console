function Get-AACLegacyAuthenticationQuery {
    <#
    .SYNOPSIS
        The queries behind Get-AACLegacyAuthentication: Azure Resource Graph
        for the resources that still accept keys, passwords or old TLS, and
        Microsoft Graph for legacy-protocol sign-ins and the tenant settings
        that allow weak or legacy authentication.
    .DESCRIPTION
        Returns @{ Graph (Resource Graph queries, an ordered hashtable);
        Entra (Microsoft Graph URIs, name -> URI or @{ Uri; MaxItems });
        Protocols (the legacy clientAppUsed values) }.

        Resource Graph:
          storage       shared key access, minimum TLS
          sql           Entra-only authentication, minimum TLS
          postgres      password authentication (flexible servers)
          localAuth     disableLocalAuth on Cosmos DB, Service Bus, Event
                        Hubs, Relay, Event Grid, SignalR, Web PubSub, App
                        Configuration, Azure AI services, AI Search,
                        Automation, Log Analytics, Application Insights,
                        IoT Hub; Batch's authentication modes
          registries    the admin user
          redis         access keys, the non-TLS port, minimum TLS
          aks           local accounts, Entra integration
          vms           Linux password authentication
          keyVaults     access policies instead of RBAC
          sites         App Service and Functions apps (their publishing
                        credentials are read per app)
        Microsoft Graph (-SignInDays of sign-ins):
          signIns|<protocol>  sign-ins per legacy protocol (up to 500)
          conditionalAccess   the policies (do any block legacy auth?)
          securityDefaults    on or off
          applications        implicit grant, public client flows, secrets
          authMethods         the authentication methods policy (SMS, voice)
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [string[]] $ResourceGroupName,

        [ValidateRange(1, 30)]
        [int] $SignInDays = 7,

        [datetime] $Now = [datetime]::UtcNow
    )

    $quote = { param([string] $Text) ConvertTo-AACKqlLiteral -Text $Text }
    $groups = @($ResourceGroupName | Where-Object { $_ })
    $in = if ($groups.Count) { " | where resourceGroup in~ ($((@($groups | ForEach-Object { & $quote $_ })) -join ', '))" } else { '' }
    $base = { param([string] $Types, [string] $Extra) "resources | where type in~ ($Types)$in | project id = tolower(id), name, type = tolower(type), resourceGroup, subscriptionId, location, $Extra" }
    $localTypes = @(
        'microsoft.documentdb/databaseaccounts', 'microsoft.servicebus/namespaces', 'microsoft.eventhub/namespaces', 'microsoft.relay/namespaces', 'microsoft.eventgrid/topics', 'microsoft.eventgrid/domains',
        'microsoft.signalrservice/signalr', 'microsoft.signalrservice/webpubsub', 'microsoft.appconfiguration/configurationstores', 'microsoft.cognitiveservices/accounts', 'microsoft.search/searchservices',
        'microsoft.automation/automationaccounts', 'microsoft.operationalinsights/workspaces', 'microsoft.insights/components', 'microsoft.devices/iothubs', 'microsoft.batch/batchaccounts'
    ) | ForEach-Object { "'$_'" }

    $graph = [ordered]@{
        storage    = & $base "'microsoft.storage/storageaccounts'" 'sharedKey = tostring(properties.allowSharedKeyAccess), tls = tostring(properties.minimumTlsVersion)'
        sql        = & $base "'microsoft.sql/servers'" 'entraOnly = tostring(properties.administrators.azureADOnlyAuthentication), tls = tostring(properties.minimalTlsVersion)'
        postgres   = & $base "'microsoft.dbforpostgresql/flexibleservers'" 'password = tostring(properties.authConfig.passwordAuth), entra = tostring(properties.authConfig.activeDirectoryAuth)'
        localAuth  = & $base ($localTypes -join ', ') 'disabled = coalesce(tostring(properties.disableLocalAuth), tostring(properties.features.disableLocalAuth), tostring(properties.DisableLocalAuth)), modes = properties.allowedAuthenticationModes, kind'
        registries = & $base "'microsoft.containerregistry/registries'" 'admin = tostring(properties.adminUserEnabled)'
        redis      = & $base "'microsoft.cache/redis'" 'nonSsl = tostring(properties.enableNonSslPort), keysOff = tostring(properties.disableAccessKeyAuthentication), tls = tostring(properties.minimumTlsVersion)'
        aks        = & $base "'microsoft.containerservice/managedclusters'" 'localOff = tostring(properties.disableLocalAccounts), entra = isnotnull(properties.aadProfile)'
        vms        = & $base "'microsoft.compute/virtualmachines'" 'passwordOff = tostring(properties.osProfile.linuxConfiguration.disablePasswordAuthentication), linux = isnotnull(properties.osProfile.linuxConfiguration)'
        keyVaults  = & $base "'microsoft.keyvault/vaults'" 'rbac = tostring(properties.enableRbacAuthorization)'
        sites      = & $base "'microsoft.web/sites'" 'kind, state = tostring(properties.state)'
    }

    $v1 = 'https://graph.microsoft.com/v1.0'
    $since = $Now.AddDays(-$SignInDays).ToString('yyyy-MM-ddTHH:mm:ssZ', [cultureinfo]::InvariantCulture)
    $protocols = @('Exchange ActiveSync', 'IMAP4', 'POP3', 'Authenticated SMTP', 'Exchange Web Services', 'MAPI Over HTTP', 'Outlook Anywhere (RPC over HTTP)', 'Autodiscover', 'Exchange Online PowerShell', 'Other clients')
    $entra = [ordered]@{}
    foreach ($p in $protocols) {
        $filter = [System.Uri]::EscapeDataString("createdDateTime ge $since and clientAppUsed eq '$p'")
        $entra["signIns|$p"] = @{ Uri = "$v1/auditLogs/signIns?`$filter=$filter&`$select=userPrincipalName,clientAppUsed,status,createdDateTime,ipAddress,appDisplayName&`$top=500"; MaxItems = 500 }
    }
    $entra['conditionalAccess'] = "$v1/identity/conditionalAccess/policies"
    $entra['securityDefaults'] = "$v1/policies/identitySecurityDefaultsEnforcementPolicy"
    $entra['applications'] = "$v1/applications?`$select=id,appId,displayName,passwordCredentials,keyCredentials,web,isFallbackPublicClient&`$top=999"
    $entra['authMethods'] = "$v1/policies/authenticationMethodsPolicy"

    @{ Graph = $graph; Entra = $entra; Protocols = $protocols }
}
