# Activity Log assessment

[Guide index](../../GUIDE.md) · [Command reference](../Azure.Admin.Console.md)

**Commands:** [`Invoke-AACActivityLogAssessment`](../Invoke-AACActivityLogAssessment.md) · [`Show-AACActivityLogEvent`](../Show-AACActivityLogEvent.md)

`Invoke-AACActivityLogAssessment` answers, for every resource: who changed it, when, and when it was
last used. Every row carries the subscription, resource group, resource name and tags.

```powershell
Invoke-AACActivityLogAssessment -SubscriptionId $sub -HtmlPath .ctivity.html                      # the last 90 days
Invoke-AACActivityLogAssessment -ManagementGroupId 'mg-landingzones' -Days 365 -TagName CostCenter, Owner -RequiredTag CostCenter -HtmlPath .ctivity-year.html
Invoke-AACActivityLogAssessment -SubscriptionId $sub -Days 180 -NoDisplay | Where-Object State -EQ 'Idle' | Sort-Object IdleDays -Descending
Invoke-AACActivityLogAssessment -SubscriptionId $sub -View Coverage -NoDisplay                      # where each subscription was read from
```

**How it reads the log, fastest first**

| Source | When | Speed and reach |
| ------ | ---- | --------------- |
| Log Analytics | The subscription's diagnostic setting sends its Activity Log to a workspace. The command finds it, or you give `-WorkspaceId` | A few queries per workspace, already summarised in the workspace and run five at a time. Seconds for 90, 180 or 365 days, limited only by the workspace's retention |
| Activity Log REST API | No export, `-Source ActivityLog`, or the workspace can't be read | Azure keeps 90 days. The window is cut into about 1,500 slices read side by side (`-SliceHours`, `-ThrottleLimit`) |

The **Coverage** view shows which source each subscription used and how far back its data goes. A
subscription that doesn't export its Activity Log, or whose workspace keeps less than the window,
gets a finding: 180 or 365 days need an export to a workspace.

**What you get**

- **Resources:** every resource, with:
  - **State:** Active, New, Quiet, Idle (no change for `-IdleDays`, 90 by default), Deleted (in the window, with who deleted it), or Gone (has activity but isn't there now).
  - **Last used:** the latest of its last Activity Log event, last change and creation, plus the number of idle days.
  - **Activity:** operations, writes, deletes, actions, failures and changes made by hand; the callers, the last operation and by whom; who made the earliest write.
- **Activity:** one row per resource, caller, operation and status, with how many times, first and last, the caller kind (user, guest, service principal, managed identity, Azure) and the caller's IP.
- **Callers:** each caller's operations, writes, deletes, failures, resources touched and when last seen.
- **Findings:**
  - **High:** guests changing resources; people changing access (role assignments, locks, policy).
  - **Medium:** keys or secrets read by people; failure hotspots; coverage gaps.
  - **Low:** changes made by hand; idle resources; a missing `-RequiredTag`.
  - **Info:** deletions in the window.

Last used is control-plane only. Data-plane use (reads, requests, sign-ins) never reaches the
Activity Log, so check an idle resource's metrics before removing it.

## One event, readable

An Activity Log event holds about sixty values, nested six levels deep. The error is JSON stored
inside a string, and who made the call is hidden in token claims. `Show-AACActivityLogEvent` flattens
each event into one row and shows it as a card:

```powershell
Show-AACActivityLogEvent -Path .\event.json                                    # saved from the portal's JSON tab; no sign-in needed
Show-AACActivityLogEvent -CorrelationId $correlationId -SubscriptionId $sub -PdfPath .\incident.pdf
Show-AACActivityLogEvent -CorrelationId $correlationId -WorkspaceId $workspaceId -Days 365 -ResolveIdentity
Invoke-AACActivityLogAssessment -SubscriptionId $sub -View Activity -NoDisplay | Where-Object Status -EQ 'Failed' | Show-AACActivityLogEvent -HtmlPath .\failures.html
```

| Section | What it shows |
| ------- | ------------- |
| When | Time, phase (begin or end request), ingestion delay |
| What | Operation, the authorised action and scope, category, channel, level |
| Result | Status, HTTP status and sub-status. For a failure: the innermost error code, message and target, the kind of failure, what to do and a docs link (read the same way as `Get-AACResourceError`) |
| Who | User, guest, service principal, managed identity or Azure; app and object ID; how it signed in (public client, client secret, certificate or federated credential, or a user's authentication methods); home or external tenant; directory roles; when the token was issued and expires; caller IP. `-ResolveIdentity` adds names from Microsoft Graph |
| Where | Subscription, resource group, type, name, location, tags, portal link |
| Trace | Correlation, operation and event IDs, tenant, hierarchy |

The token's opaque values (`aio`, `rh`, `uti`, `xms_*`) are left out. `-IncludeClaims` adds every
claim, as `Claim:<name>` columns and a Claims tab. Views: Event (one row per event), Detail (the
cards), Error (failures grouped by code), Caller and Claim. Rows from
`Invoke-AACActivityLogAssessment -View Activity` carry the latest operation's correlation ID and,
for failures, `ErrorCode` and `ErrorMessage`, so you can pipe them in for the full events.
