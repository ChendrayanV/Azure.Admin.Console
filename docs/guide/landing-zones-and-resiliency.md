# Landing zones and resiliency

[Guide index](../../GUIDE.md) · [Command reference](../Azure.Admin.Console.md)

**Commands:** [`Invoke-AACLandingZoneAssessment`](../Invoke-AACLandingZoneAssessment.md) · [`Invoke-AACResiliencyAssessment`](../Invoke-AACResiliencyAssessment.md) · [`Get-AACResiliencyRecommendation`](../Get-AACResiliencyRecommendation.md) · [`Test-AACAlzPolicy`](../Test-AACAlzPolicy.md)

Two catalogues of Resource Graph queries that ship with the module, at pinned commits. Both are read-only and need only Reader.

```powershell
Invoke-AACLandingZoneAssessment -ManagementGroupId 'mg-landingzones' -HtmlPath .\LandingZone.html
Invoke-AACResiliencyAssessment -SubscriptionId '<id>' -Impact High -Status Fail
```

Neither gives a score. Many checks can't be answered by a query, and a percentage would claim more than was measured.

## Azure Landing Zone checklist

About 130 of the 206 checklist items can be queried. These are community queries from [alz-graph-queries](https://github.com/martinopedal/alz-graph-queries), and they vary, so a status says what its evidence can bear:

| Status | Meaning |
|---|---|
| Fail | Found something that doesn't comply |
| Review | As Fail, but judged by a name, which proves little |
| Pass | Found things, and all comply |
| Present | The query can only say the resource is there |
| No evidence | Nothing came back: not used, or not needed. Not a pass |
| Manual | Resource Graph can't answer this one; the reason says why |
| Not checked | The query failed |

A failed check is a question to answer, not always a fault: many items depend on your design.

## Azure Proactive Resiliency Library

`Get-AACResiliencyRecommendation` lists what APRL recommends, offline. `Invoke-AACResiliencyAssessment` runs APRL's own queries against your resources. Only about half of its recommendations have one: the rest show as Manual when you use that resource type, so a report with no failures doesn't mean they are met.

Both commands take `-SuppressionFile` and `-PreviousPath`: see [Accepting findings and tracking change](accepting-findings-and-tracking-change.md).
