# Storage account assessment

[Guide index](../../GUIDE.md) · [Command reference](../Azure.Admin.Console.md)

**Commands:** [`Invoke-AACStorageAccountAssessment`](../Invoke-AACStorageAccountAssessment.md)

`Invoke-AACStorageAccountAssessment` brings Azure Monitor's **Storage
accounts** workbook to the prompt and the reports, and adds what the
workbook doesn't check:

```powershell
Invoke-AACStorageAccountAssessment                                              # every account, the last day
Invoke-AACStorageAccountAssessment -TimeRange 4h                                # the workbook's default period
Invoke-AACStorageAccountAssessment -ResourceGroupName 'rg-data' -HtmlPath .\Storage.html -PdfPath .\Storage.pdf
Invoke-AACStorageAccountAssessment -View Finding -NoDisplay | Where-Object Signal -EQ 'Security'
Invoke-AACStorageAccountAssessment -NoDisplay | Sort-Object UsedGB -Descending | Select-Object -First 10 Account, UsedGB, AccessTier, LifecycleRules
```

- **Overview** (the workbook's first tab): transactions, end-to-end and
  server latency, and errors by response type, plus availability, ingress
  and egress. Response types are grouped as Success, Throttling, Server,
  Authorization, Network and Client. Client errors (404, 409) are often
  normal, so they aren't counted as errors.
- **Capacity** (the workbook's second tab): used capacity and blob, file,
  queue and table capacity, with blob, container and file share counts. It
  shows the latest value, read over at least two days, because Azure reports
  capacity hourly or daily.
- **Security & protection:**
  - HTTPS, TLS, anonymous blob access, network access and private endpoints;
  - shared keys, key age, and key and SAS expiry policies;
  - cross-tenant replication, encryption, blob logs and Defender for
    Storage;
  - redundancy, blob, container and file share soft delete, versioning,
    change feed, point-in-time restore and lifecycle rules.
- **Findings**, worst first, under seven signals: availability, errors,
  throttling, latency, security, protection and cost. The heat map scores
  each account 0-100 on every signal, and clicking a cell in the HTML report
  lists its findings.

It reads Resource Graph, Azure Monitor metrics and each account's service
settings: Reader is enough. It reads no data and no keys.
