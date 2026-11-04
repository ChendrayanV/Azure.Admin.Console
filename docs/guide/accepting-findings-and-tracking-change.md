# Accepting findings and tracking change

[Guide index](../../GUIDE.md) · [Command reference](../Azure.Admin.Console.md)

**Commands:** [`Invoke-AACAksAssessment`](../Invoke-AACAksAssessment.md) · [`Invoke-AACM365Assessment`](../Invoke-AACM365Assessment.md) · [`Invoke-AACADOAssessment`](../Invoke-AACADOAssessment.md) · [`Invoke-AACLandingZoneAssessment`](../Invoke-AACLandingZoneAssessment.md) · [`Invoke-AACResiliencyAssessment`](../Invoke-AACResiliencyAssessment.md)

These commands give every finding a `FindingKey`: 16 characters that stay the same from run to run, though its wording or counts change.

## Accepting a finding

`-SuppressionFile` takes a JSON file of the findings you have reviewed. Name one by its key, or by source and rule, with a reason. An expiry date is optional:

```json
[
  { "key": "a1b2c3d4e5f60718", "reason": "Accepted by the security board, 2026-09" },
  { "source": "Aks", "rule": "Private API server", "subject": "aks-dev*", "reason": "Dev clusters stay public", "expires": "2027-01-01" }
]
```

A suppressed finding leaves the counts, and the report lists it with its reason, so the decision stays visible. An expired entry is reported and ignored. An entry that matched nothing is reported too. A file that can't be understood stops the command before it reads anything from Azure.

## What changed since last time

`-PreviousPath` takes the findings CSV of an earlier run, or the folder a run's `-CsvPath` wrote to. Each finding's `Change` is then `New` or `Open`, and the report lists what has been resolved. A finding suppressed since isn't called resolved. A CSV with no `FindingKey` column stops the command, rather than calling everything new.

```powershell
Invoke-AACM365Assessment -CsvPath .\m365-november -PreviousPath .\m365-october -SuppressionFile .\accepted.json
```

For the Azure DevOps assessment, use `-View Finding -CsvPath` to write the findings, and `-View SuppressedFinding` or `-View ResolvedFinding` for the others. Its per-pipeline and per-project finding counts still include suppressed findings.

The other commands that produce findings don't take these parameters yet.
