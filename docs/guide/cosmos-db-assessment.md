# Cosmos DB assessment

[Guide index](../../GUIDE.md) · [Command reference](../Azure.Admin.Console.md)

**Commands:** [`Invoke-AACCosmosDBAssessment`](../Invoke-AACCosmosDBAssessment.md)

`Invoke-AACCosmosDBAssessment` looks at every Azure Cosmos DB account, in
every API (NoSQL, MongoDB, Cassandra, Gremlin, Table):

```powershell
Invoke-AACCosmosDBAssessment                                                    # every account, the last day
Invoke-AACCosmosDBAssessment -NoDisplay | Where-Object Throttled | Select-Object Account, Throttled, ThrottleRate, NormalizedRuMax, ProvisionedRU, AutoscaleMaxRU
Invoke-AACCosmosDBAssessment -View Container -NoDisplay | Where-Object ThroughputMode -EQ 'Manual' | Sort-Object RU -Descending
Invoke-AACCosmosDBAssessment -ResourceGroupName 'rg-data' -TimeRange 7d -HtmlPath .\CosmosDB.html -PdfPath .\CosmosDB.pdf
```

- **Overview:** service availability, requests by status code - rate
  limited (429), server errors (5xx), client errors (404, 409 and 412 are
  counted apart: they are often normal) - request units, the busiest
  partition's share of its throughput, server-side latency, and the latest
  data, index and document counts.
- **Containers:** every database and container with its partition key, its
  throughput (autoscale, manual, shared database or serverless) and RU/s,
  default TTL, analytical store and indexing.
- **Security & resilience:** network access and private endpoints, account
  keys, TLS, encryption, logs and Defender for Azure Cosmos DB; regions,
  automatic failover, availability zones, consistency and backup.
- **Findings**, worst first, under six signals: availability, throttling,
  errors, security, resilience and cost - rate limiting, running close to
  the throughput, single regions, no failover, periodic backup only, open
  networks, keys, throughput higher than needed and many small containers
  with their own throughput. The heat map scores each account 0-100 on
  every signal.

It reads Resource Graph, Resource Manager and Azure Monitor metrics: Reader
is enough. It reads no documents and no keys.
