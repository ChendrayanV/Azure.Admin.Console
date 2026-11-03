# Function App assessment

[Guide index](../../GUIDE.md) · [Command reference](../Azure.Admin.Console.md)

**Commands:** [`Invoke-AACFunctionAppAssessment`](../Invoke-AACFunctionAppAssessment.md)

`Invoke-AACFunctionAppAssessment` assesses Azure Function Apps - Windows,
Linux, containers and Flex Consumption - read-only, REST only:

```powershell
Invoke-AACFunctionAppAssessment -HtmlPath .\Functions.html                       # every app you can see
Invoke-AACFunctionAppAssessment -Name 'func-orders-*' -TimeRange 30d -PdfPath .\Orders.pdf
Invoke-AACFunctionAppAssessment -View Finding -NoDisplay | Where-Object Pillar -EQ 'Security'
Invoke-AACFunctionAppAssessment -View Activity -ActivityDays 30 -NoDisplay | Where-Object Kind -EQ 'Configuration change'
```

- **App and plan:** hosting (Consumption, Flex Consumption, Elastic Premium,
  Dedicated, App Service Environment, Container Apps), SKU, instances, burst,
  zone redundancy, the plan's CPU and memory.
- **Usage over `-TimeRange` (7d):** executions, GB-seconds, requests, 5xx and
  4xx, error rate, response time, memory; an estimated monthly cost on
  Consumption (before the free grant); idle apps.
- **Functions:** every function with its trigger (HTTP and its auth level,
  timer and its schedule, queue, Service Bus, Event Hubs...) and bindings.
- **Runtime:** the Functions runtime, the language version against its end
  of support, and the .NET in-process model (support ends 10 November 2026).
- **Configuration:** every setting that matters, by area, and the app
  settings by name and kind (Key Vault reference, identity-based, key or
  connection string, plain) - values are never read into the report. Listing
  app settings needs Website Contributor (or a custom role with
  `Microsoft.Web/sites/config/list/action`); without it they are left out and
  said so. `-SkipSettings` doesn't ask.
- **Networking, deployment, backups, connections:** inbound access, the SCM
  site, VNet integration, CORS; the deployment center, recent deployments and
  slots; backups where the plan supports them; Service Connector connections
  and the Key Vaults, storage accounts, Service Bus and Cosmos DB accounts
  named in settings, with how each authenticates.
- **Activity Log (`-ActivityDays`, 7):** restarts, stops, configuration
  changes, deployments, slot swaps, settings and keys read - who, when, and
  whether it worked.
- **Well-Architected, PSRule, Advisor, Defender:** about 30 checks across the
  five pillars, PSRule for Azure on the apps and plans (`-SkipPSRule`), and
  Advisor and Defender recommendations - every failure a finding.

The HTML report has a tab per audience: a service summary for service
delivery managers, apps and plans for architects, configuration and
networking for administrators, findings for IT security - an App selector
that filters every tab, and hover cards.
