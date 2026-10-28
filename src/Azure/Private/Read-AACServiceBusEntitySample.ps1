function Read-AACServiceBusEntitySample {
    <#
    .SYNOPSIS
        Reads queues' and topic subscriptions' live counts several times, a
        while apart - a short backlog trend for someone with no access to
        the namespace's metrics.
    .DESCRIPTION
        For Show-AACServiceBusEntity -Sample. Only what an entity role can
        read: each queue, and each topic's subscriptions, -Count times,
        -Interval apart. It shows how the backlog moved, not what was sent
        or received (those are namespace metrics).

        Returns @(@{ Time (UTC); Entity (queue, or topic/subscription);
        Kind ('Queue' or 'Subscription'); Active; DeadLettered; Scheduled;
        SizeMB (queues) }) - a row per entity per read; a read that fails is
        left out.
    #>
    [CmdletBinding()]
    [OutputType([hashtable[]])]
    param(
        [Parameter(Mandatory)]
        [string] $NamespaceId,

        # The entities Read-AACServiceBusEntityState could read: @{ Name; Kind }.
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Entity,

        [ValidateRange(2, 120)]
        [int] $Count = 5,

        [timespan] $Interval = [timespan]::FromSeconds(30),

        [ValidateRange(1, 32)]
        [int] $ThrottleLimit = 12,

        # Called with (read number, count) before each read.
        [scriptblock] $OnSample
    )

    $api = 'api-version=2021-11-01'
    $ns = $NamespaceId.TrimEnd('/')
    $targets = @(foreach ($e in $Entity) {
            $segment = [System.Uri]::EscapeDataString([string]$e.Name)
            if ($e.Kind -eq 'Queue') { @{ Name = [string]$e.Name; Kind = 'Queue'; Uri = "$ns/queues/${segment}?$api" } }
            elseif ($e.Kind -eq 'Topic') { @{ Name = [string]$e.Name; Kind = 'Topic'; Uri = "$ns/topics/$segment/subscriptions?$api" } }
        })
    $rows = [System.Collections.Generic.List[hashtable]]::new()
    if (-not $targets.Count) { return }
    $countOf = { param($Properties, [string] $Key) if ($Properties -is [System.Collections.IDictionary] -and $Properties['countDetails'] -is [System.Collections.IDictionary] -and $null -ne $Properties['countDetails'][$Key]) { [long]$Properties['countDetails'][$Key] } else { [long]0 } }
    for ($i = 1; $i -le $Count; $i++) {
        if ($OnSample) { & $OnSample $i $Count }
        $answers = Invoke-AACArmParallel -Uri @($targets | ForEach-Object { $_.Uri }) -ThrottleLimit $ThrottleLimit
        $time = [datetime]::UtcNow
        foreach ($t in $targets) {
            $answer = $answers[$t.Uri]
            if ([int]$answer['Status'] -ne 200) { continue }
            if ($t.Kind -eq 'Queue') {
                $p = $answer['Body']['properties']
                $rows.Add(@{ Time = $time; Entity = $t.Name; Kind = 'Queue'; Active = & $countOf $p 'activeMessageCount'; DeadLettered = & $countOf $p 'deadLetterMessageCount'; Scheduled = & $countOf $p 'scheduledMessageCount'; SizeMB = [Math]::Round([double]$p['sizeInBytes'] / 1MB, 3) })
            }
            else {
                foreach ($s in @($answer['Items'] | Where-Object { $_ -is [System.Collections.IDictionary] })) {
                    $p = $s['properties']
                    $rows.Add(@{ Time = $time; Entity = "$($t.Name)/$($s['name'])"; Kind = 'Subscription'; Active = & $countOf $p 'activeMessageCount'; DeadLettered = & $countOf $p 'deadLetterMessageCount'; Scheduled = & $countOf $p 'scheduledMessageCount'; SizeMB = $null })
                }
            }
        }
        if ($i -lt $Count) { Start-Sleep -Milliseconds ([int]$Interval.TotalMilliseconds) }
    }
    $rows.ToArray()
}
