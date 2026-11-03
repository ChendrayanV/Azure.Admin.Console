# Architecture design

[Guide index](../../GUIDE.md) · [Command reference](../Azure.Admin.Console.md)

**Commands:** [`Export-AACArchitectureDecision`](../Export-AACArchitectureDecision.md) · [`Get-AACArchitecturePattern`](../Get-AACArchitecturePattern.md) · [`New-AACArchitectureBrief`](../New-AACArchitectureBrief.md) · [`New-AACArchitectureDesign`](../New-AACArchitectureDesign.md) · [`New-AACArchitectureDiagram`](../New-AACArchitectureDiagram.md) · [`Test-AACArchitectureDesign`](../Test-AACArchitectureDesign.md)

Six commands take a workload from requirements to a validated, drawn and
recorded design - offline (only the landing zone's policy is read from
Azure, and `-Offline` skips that):

```powershell
$brief = New-AACArchitectureBrief -Name 'orders-api' -OutPath .\orders-api.brief.json      # the probe questions, at the prompt
Get-AACArchitecturePattern -Brief $brief                                                    # the patterns that fit, and why
$design = Get-AACArchitecturePattern -Brief $brief -RecommendedOnly -NoDisplay |
    New-AACArchitectureDesign -Brief $brief -Region westeurope, northeurope -LandingZone 'mg-landingzones' -OutPath .\orders-api.design.json
Test-AACArchitectureDesign -Design $design -GuardrailPath .\guardrails.psd1 -HtmlPath .\orders-api.validation.html
New-AACArchitectureDiagram -Design $design -Path .\docs\architecture                        # .mmd, .md and .drawio
Export-AACArchitectureDecision -Design $design -Path .\docs\adr -Owner 'Platform architecture'
```

| Step | What it does |
| --- | --- |
| Brief | About 20 probe questions, each tied to a Well-Architected pillar: workload kind and criticality; RTO, RPO, SLA, degraded running; data classification, frameworks, exposure, identity; read/write mix, response target, load, geographies, data store; budget and baseline; deployment, observability, landing zone. `-Answer` or `-AnswerPath` gives answers; `?` means "don't know" - the default is used and the question stays open; unanswered questions are recorded as assumptions. |
| Patterns | Fifteen cloud design patterns from the Azure Architecture Center, each with fit rules over the answers (and the reason), its effect on each pillar, and a score weighted by what the brief values. |
| Design | Components from the answers and the patterns (compute for the workload kind, the data store, Front Door or Application Gateway with the WAF, hub and spoke with private DNS and Azure Firewall where the data and exposure call for them, Key Vault, monitoring, a budget, the pipeline with its PSRule gate), their settings (zones, private endpoints, identity, TLS, purge protection), a second region when the RTO or SLA needs one, and the landing zone's inherited policy and allowed locations. `-Override` changes any component. |
| Validate | Rules with a pillar, severity, the built-in Azure Policy and PSRule for Azure rule they correspond to, the Advisor category and the fix. Blocking: what an inherited Deny policy or your guardrails would refuse. `-Accept` records an accepted risk; `-FailOnGap` fails a pipeline on open Blocking or High findings. |
| Diagram | Mermaid, Markdown (renders in Azure DevOps wikis, GitHub, VS Code) and draw.io - components coloured by their worst finding, with layers for WAF, Azure Policy, guardrails, the PSRule gate and Azure Recommendations. The draw.io has five pages: Cover, Architecture (Azure icons in landing zone, region, virtual network and data boxes), Policy and compliance, Findings and Legend. |
| Decisions | ADRs: hosting and topology, each pattern, each accepted risk (reason, owner, review date), with an index of open decisions and assumptions. |

Guardrails are a .psd1 or .json file of the organisation's own rules:
`@{ AllowedRegions = @('westeurope', 'northeurope'); DenyPublicEndpoint = $true;
DeniedSkus = @('Basic*'); RequiredTags = @('CostCenter', 'Owner') }`. Every
brief, design and decision record carries the catalog version it was made with,
and Test-AACArchitectureDesign says when a design was made with an older one.
The policy display names and PSRule rule names in the catalog are references to
verify against current Microsoft data.
