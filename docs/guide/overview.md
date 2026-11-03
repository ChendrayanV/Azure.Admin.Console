# Overview

[Guide index](../../GUIDE.md) · [Command reference](../Azure.Admin.Console.md)

Azure admin reports and checks from PowerShell, over plain REST. No Az or
Microsoft.Graph modules, and no app registration.

<p align="center">
  <a href="https://www.youtube.com/watch?v=xBkStQ1H2OU">
    <img src="https://img.youtube.com/vi/odHW8du6dUk/maxresdefault.jpg" alt="Azure.Admin.Console video walkthrough" width="500">
  </a>
</p>

- **Azure Advisor report.** Every Advisor recommendation (Cost, Security,
  Reliability, Operational excellence, Performance) flattened to one row per
  resource, with estimated savings, retirement dates and postponed/dismissed
  status, shown as a colour-coded console view.
- **Azure Firewall rules.** Every Firewall Policy rule (DNAT, network,
  application) with IP Groups resolved to names and addresses, shown one
  colour-coded table per rule collection.
- **Tenant inventory.** Management groups, subscriptions, resource groups
  and resources as one tree, with counts, the Defender for Cloud secure score
  and findings, and - with `-Cost` - what everything costs, at every level.
- **Security posture.** Microsoft Defender for Cloud and Azure Policy in
  one report: secure scores, recommendations by control with remediation
  links, active alerts, Defender plans, regulatory compliance traced to the
  failing resources, and policy compliance.
- **Network security groups.** Every NSG assessed: where it's applied, every
  rule in evaluation order, flow logs and diagnostic settings, and findings
  by severity with what to do.
- **Azure Policy compliance.** Every resource's policy states, with their
  initiative, assignment and effect - by management group, subscription or
  resource group - and compliance per assignment, policy and scope.
- **Entra ID group membership.** Who is in your groups - direct members and
  everyone in nested groups - flattened to one row per group and member,
  with guests and disabled accounts flagged. Read from Microsoft Graph.
- **Resource map.** A diagram of one or more resource groups in your
  browser, with Azure icons, VNets and subnets, network paths, NSGs and
  route tables. Saves as PNG or JPEG.
- **PSRule for Azure.** Its 500+ Well-Architected rules, the module's own
  naming and tag rules, and your custom rules, run on the live estate. You
  can leave rules out by name or wildcard.
- **Fast.** One pooled HTTPS connection for every call, and independent
  reads in parallel within each Azure API's limits.
- **Application Insights.** Your application's exceptions, flattened, or any
  KQL query, from a Log Analytics workspace or an Application Insights
  resource.
- **Resource and cost charts.** Colourful console charts of what you run (by
  type, region, resource group or subscription) and what it costs (month to
  date by subscription and service, and the monthly trend), plus a full
  resource inventory.
- **Output your way.** A console view, PowerShell objects, CSV, PDF or an
  interactive HTML report, from the same command.

Every command reads; only `Deploy-AACStorageAccount` writes, and it plans,
checks Azure Policy and PSRule, and asks first (`-WhatIf` changes nothing).
Each command's help lists the permissions it needs.
