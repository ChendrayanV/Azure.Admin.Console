function Read-AACServiceBusEntity {
    <#
    .SYNOPSIS
        Reads what Invoke-AACServiceBusAssessment needs from each namespace
        through Resource Manager - its queues, topics and their
        subscriptions, network rules, SAS rules, geo-disaster recovery and
        where its logs go - many requests at once.
    .DESCRIPTION
        Two rounds through Invoke-AACArmParallel (Reader is enough):
          1. per namespace: queues, topics, networkRuleSets/default,
             authorizationRules, disasterRecoveryConfigs and the diagnostic
             settings
          2. per topic: its subscriptions
        A request that fails is kept with its error; the rest carry on.

        Returns @{ namespace id = @{ Queues; Topics; Network; Rules;
        GeoDr; Logs (each Invoke-AACArmParallel's result); Subscriptions
        (@{ topic id = that topic's result }) } }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]] $NamespaceId,

        [ValidateRange(1, 32)]
        [int] $ThrottleLimit = 12,

        [scriptblock] $OnProgress
    )

    $api = 'api-version=2021-11-01'
    $parts = [ordered]@{
        Queues  = "queues?$api"
        Topics  = "topics?$api"
        Network = "networkRuleSets/default?$api"
        Rules   = "authorizationRules?$api"
        GeoDr   = "disasterRecoveryConfigs?$api"
        Logs    = 'providers/Microsoft.Insights/diagnosticSettings?api-version=2021-05-01-preview'
    }
    $uris = [ordered]@{}
    foreach ($id in $NamespaceId) { foreach ($part in $parts.Keys) { $uris["$id|$part"] = "$id/$($parts[$part])" } }
    $answers = if ($uris.Count) { Invoke-AACArmParallel -Uri @($uris.Values) -ThrottleLimit $ThrottleLimit -OnProgress $OnProgress } else { @{} }

    $out = @{}
    foreach ($id in $NamespaceId) { $out[$id] = @{ Queues = $null; Topics = $null; Network = $null; Rules = $null; GeoDr = $null; Logs = $null; Subscriptions = @{} } }
    foreach ($key in $uris.Keys) {
        $id, $part = $key -split '\|', 2
        $out[$id][$part] = $answers[$uris[$key]]
    }

    # Round 2: each topic's subscriptions (where the messages wait).
    $topicUris = [ordered]@{}
    foreach ($id in $NamespaceId) {
        $topics = $out[$id].Topics
        if (-not $topics -or $topics['Error']) { continue }
        foreach ($topic in @($topics['Items'] | Where-Object { $_ })) { $topicUris["$id|$([string]$topic['id'])"] = "$([string]$topic['id'])/subscriptions?$api" }
    }
    $topicAnswers = if ($topicUris.Count) { Invoke-AACArmParallel -Uri @($topicUris.Values) -ThrottleLimit $ThrottleLimit -OnProgress $OnProgress } else { @{} }
    foreach ($key in $topicUris.Keys) {
        $id, $topicId = $key -split '\|', 2
        $out[$id].Subscriptions[$topicId.ToLowerInvariant()] = $topicAnswers[$topicUris[$key]]
    }
    $out
}
