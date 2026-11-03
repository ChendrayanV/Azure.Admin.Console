# Service Bus assessment

[Guide index](../../GUIDE.md) · [Command reference](../Azure.Admin.Console.md)

**Commands:** [`Invoke-AACServiceBusAssessment`](../Invoke-AACServiceBusAssessment.md) · [`Show-AACServiceBusEntity`](../Show-AACServiceBusEntity.md)

`Invoke-AACServiceBusAssessment` looks at every Service Bus namespace - and
every queue, topic and subscription in it:

```powershell
Invoke-AACServiceBusAssessment                                                  # every namespace, the last day
Invoke-AACServiceBusAssessment -View Entity -NoDisplay | Where-Object DeadLetters | Sort-Object DeadLetters -Descending
Invoke-AACServiceBusAssessment -ResourceGroupName 'rg-integration' -TimeRange 7d -HtmlPath .\ServiceBus.html -PdfPath .\ServiceBus.pdf
Invoke-AACServiceBusAssessment -View Finding -NoDisplay | Where-Object Signal -EQ 'Security'
```

- **Overview:** requests, server and client errors and throttled requests
  over the period, messages in and out, and for Premium the CPU and memory
  of the messaging units.
- **Entities:** every queue, topic and subscription as it is now - active,
  dead-lettered, transfer dead-lettered and scheduled messages, size against
  its maximum, delivery and lock settings, and when it was last used.
- **Security & resilience:** TLS, SAS keys (and namespace-wide Manage
  keys), network access and private endpoints, encryption, logs, zone
  redundancy and geo-disaster recovery.
- **Findings**, worst first, under six signals: health, capacity, messages,
  security, resilience and cost - dead letters, entities filling up (sends
  fail at 100%), backlogs, topics with no subscription, expired messages
  dropped, throttling, CPU and memory, SAS keys, open networks, no logs, no
  zones or Geo-DR, idle entities and too many messaging units. The heat map
  scores each namespace 0-100 on every signal.

It reads Resource Graph, Resource Manager and Azure Monitor metrics: Reader
is enough. It reads no messages and no keys.

## Service Bus entities, as you can see them

The assessment needs the namespace. Application teams often hold a role on
their own queues and topics only - *Azure Service Bus Data Sender* or *Data
Receiver* - and `Show-AACServiceBusEntity` is for them as much as for the
platform team. It works out what your sign-in can read, entity by entity:

```powershell
Show-AACServiceBusEntity -NamespaceId $namespaceId -EntityName 'orders'                       # one queue or topic
Show-AACServiceBusEntity -NamespaceId $namespaceId -EntityName 'orders-*' -TimeRange 7d -HtmlPath .\sb.html
Show-AACServiceBusEntity -NamespaceId $namespaceId -EntityName 'orders' -Sample 10 -SampleInterval 00:00:30
Show-AACServiceBusEntity -NamespaceId $namespaceId -EntityName 'events' -View Subscription -NoDisplay | Where-Object DeadLettered
```

| Your role | What you see |
|---|---|
| On the namespace (Reader, Monitoring Reader, Data Owner) | Every queue and topic (wildcards, or no `-EntityName` for all), their live state, and their Azure Monitor metrics over `-TimeRange` |
| On the entity only (Data Sender or Receiver) | The named entities' live state. Service Bus publishes metrics on the namespace, so an entity role can't read them; `-Sample` reads the live counts a few times instead, for a backlog trend |
| None | The entity is listed as *No role*, with the role to ask for |

- **Live state:** active, dead-lettered, scheduled, transfer and transfer
  dead-lettered messages, size against the maximum, status and when it was
  last used. A topic's counts are the sum of its subscriptions'.
- **Dead-letter, Subscriptions, Configuration:** each queue's and
  subscription's dead-letter queue and why messages land there; each topic's
  subscriptions; every setting (lock, max deliveries, TTL, sessions,
  duplicate detection, forwarding, partitioning, auto-delete).
- **Metrics:** messages in and out, completed and abandoned, requests,
  server and user errors, throttling, backlog over time, size and send
  latency per queue or topic - total, average, peak and a trend (▁▃▅█) - and
  a Premium namespace's CPU and memory.
- **Findings:** dead-letters, auto-forwarding failing, entities filling up
  or disabled, throttling, server errors, messages arriving with none
  received, a growing backlog (from metrics or samples), idle entities,
  expired messages dropped.
- **What you can see:** for each entity, what this sign-in could read and
  the role that would show the rest.

With only an entity role you can't look the namespace up, so ask the
platform team for its resource ID.
