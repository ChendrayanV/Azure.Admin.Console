function Read-AACFunctionAppDetail {
    <#
    .SYNOPSIS
        Reads what Resource Graph doesn't hold about each function app, from
        Azure Resource Manager: its configuration, functions and triggers,
        deployment center, publishing credentials, backups, authentication,
        Service Connector connections, diagnostic settings, health, locks,
        Activity Log - and, with the permission, its app settings and
        connection strings.
    .DESCRIPTION
        GETs run in parallel (Invoke-AACArmParallel), a few per app:
          config/web                      site configuration (TLS, FTPS,
                                          HTTP/2, Always On, runtime, access
                                          restrictions, CORS, health check,
                                          scale limits, deployment source)
          functions                       each function, its trigger and
                                          bindings (read from the app's host:
                                          empty when the app is stopped or
                                          its host can't be reached)
          sourcecontrols/web, deployments the deployment center and recent
                                          deployments
          basicPublishingCredentialsPolicies/scm and /ftp
          backups, config/authsettingsV2, Microsoft.ServiceLinker/linkers,
          diagnosticSettings, availabilityStatuses/current, locks
          the Activity Log                every management event on the app
                                          over -ActivityDays
        POSTs, one at a time (Invoke-AACArmRequest):
          config/appsettings/list, config/connectionstrings/list - these
          need Microsoft.Web/sites/config/list/action (Website Contributor,
          or a custom role); Reader gets 403, recorded as the reason.

        Returns @{ app ID (lower case) = @{ Web; Functions; SourceControl;
        Deployments; ScmBasic; FtpBasic; Backups; Auth; Linkers;
        Diagnostics; Health; Locks; Activity (each @{ Body; Items; Error });
        AppSettings (@{ name = value } or $null); AppSettingsError;
        ConnectionStrings (@{ name = type } or $null) } }. Setting values
        stay inside the module: the assessment reads them to classify a
        setting (a Key Vault reference, an identity-based connection, a key)
        and returns names only.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $AppId,

        [ValidateRange(1, 90)]
        [int] $ActivityDays = 7,

        [switch] $SkipSettings,

        [ValidateRange(1, 32)]
        [int] $ThrottleLimit = 12,

        [scriptblock] $OnProgress,

        [datetime] $Now = [datetime]::UtcNow
    )

    $api = 'api-version=2023-12-01'
    $iso = { param([datetime] $When) $When.ToString('yyyy-MM-ddTHH:mm:ssZ', [cultureinfo]::InvariantCulture) }
    $parts = [ordered]@{
        Web           = "config/web?$api"
        Functions     = "functions?$api"
        SourceControl = "sourcecontrols/web?$api"
        Deployments   = "deployments?$api"
        ScmBasic      = "basicPublishingCredentialsPolicies/scm?$api"
        FtpBasic      = "basicPublishingCredentialsPolicies/ftp?$api"
        Backups       = "backups?$api"
        Auth          = "config/authsettingsV2?$api"
        Linkers       = 'providers/Microsoft.ServiceLinker/linkers?api-version=2022-05-01'
        Diagnostics   = 'providers/Microsoft.Insights/diagnosticSettings?api-version=2021-05-01-preview'
        Health        = 'providers/Microsoft.ResourceHealth/availabilityStatuses/current?api-version=2022-10-01'
        Locks         = 'providers/Microsoft.Authorization/locks?api-version=2020-05-01'
    }
    $uris = [ordered]@{}
    foreach ($id in @($AppId | Where-Object { $_ })) {
        $key = $id.ToLowerInvariant()
        foreach ($part in $parts.Keys) { $uris["$key|$part"] = "$id/$($parts[$part])" }
        $sub = ($id -split '/')[2]
        $filter = "eventTimestamp ge '$(& $iso $Now.AddDays(-$ActivityDays))' and eventTimestamp le '$(& $iso $Now)' and resourceUri eq '$id'"
        $uris["$key|Activity"] = "/subscriptions/$sub/providers/Microsoft.Insights/eventtypes/management/values?api-version=2015-04-01&`$filter=$([System.Uri]::EscapeDataString($filter))"
    }
    $answers = if ($uris.Count) { Invoke-AACArmParallel -Uri @($uris.Values) -ThrottleLimit $ThrottleLimit -OnProgress $OnProgress } else { @{} }

    $out = @{}
    foreach ($key in $uris.Keys) {
        $id, $part = $key -split '\|', 2
        if (-not $out.ContainsKey($id)) { $out[$id] = @{ AppSettings = $null; AppSettingsError = ''; ConnectionStrings = $null } }
        $answer = $answers[$uris[$key]]
        $out[$id][$part] = if ($answer -is [System.Collections.IDictionary]) { $answer } else { @{ Body = $null; Items = $null; Error = 'No answer.' } }
    }

    # App settings and connection strings: POST list actions, which Reader can't call - one at a time,
    # and a 403 on the first means the rest will fail too, so stop asking.
    if (-not $SkipSettings) {
        $denied = ''
        foreach ($id in @($AppId | Where-Object { $_ })) {
            $key = $id.ToLowerInvariant()
            if ($denied) { $out[$key].AppSettingsError = $denied; continue }
            try {
                $body = Invoke-AACArmRequest -Method Post -Uri "$id/config/appsettings/list?$api"
                $settings = @{}
                $values = if ($body -is [System.Collections.IDictionary]) { $body['properties'] } else { $null }
                if ($values -is [System.Collections.IDictionary]) { foreach ($name in $values.Keys) { $settings[[string]$name] = [string]$values[$name] } }
                $out[$key].AppSettings = $settings
                $strings = Invoke-AACArmRequest -Method Post -Uri "$id/config/connectionstrings/list?$api"
                $types = @{}
                $items = if ($strings -is [System.Collections.IDictionary]) { $strings['properties'] } else { $null }
                if ($items -is [System.Collections.IDictionary]) { foreach ($name in $items.Keys) { $types[[string]$name] = [string]$items[$name]['type'] } }
                $out[$key].ConnectionStrings = $types
            }
            catch {
                $status = [string]$_.Exception.Data['StatusCode']
                $reason = if ($status -eq '403') { 'Your account can''t list app settings (it needs Microsoft.Web/sites/config/list/action - Website Contributor, or a custom role).' } else { "App settings couldn't be read: $($_.Exception.Message)" }
                $out[$key].AppSettingsError = $reason
                if ($status -eq '403') { $denied = $reason }
            }
        }
    }
    else {
        foreach ($key in @($out.Keys)) { $out[$key].AppSettingsError = 'Not read (-SkipSettings).' }
    }
    $out
}
