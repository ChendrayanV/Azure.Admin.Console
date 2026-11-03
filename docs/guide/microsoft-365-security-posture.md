# Microsoft 365 security posture

[Guide index](../../GUIDE.md) · [Command reference](../Azure.Admin.Console.md)

**Commands:** [`Invoke-AACM365Assessment`](../Invoke-AACM365Assessment.md)

`Invoke-AACM365Assessment` discovers a Microsoft 365 tenant and assesses its
security posture with the Microsoft Graph REST API. It uses no AzureAD,
MSOnline, AzureADPreview or Microsoft.Graph modules, and one Graph token for
every call.

A Graph token only carries the permissions consented to the app you sign in
with. `Connect-AAC`'s default (the Azure CLI) can read the directory, but not
Conditional Access, Intune or Secure Score. Sign in once with the read-only
permissions the report needs, for example with Microsoft Graph Command Line
Tools after an admin has consented:

```powershell
Connect-AAC -ClientId 14d82eec-204b-4c2f-b7e8-296a70dab67e `
    -Scope ((Invoke-AACM365Assessment -ListPermission) + 'offline_access', 'openid', 'profile')

Invoke-AACM365Assessment -HtmlPath .\M365.html -CsvPath .\m365      # every section
Invoke-AACM365Assessment -Section Entra                               # Entra ID only
(Invoke-AACM365Assessment -NoDisplay).Registration | Where-Object { $_.Admin -eq 'Yes' -and $_.MfaRegistered -eq 'No' }
```

Your account also needs a directory role that can read them, for example
Global Reader. A service principal works too, with the same permissions as
application permissions (`Connect-AAC -ClientId ... -CertificatePath ...`).
Whatever Graph refuses is listed in the Permissions tab with the permission it
needs; the rest of the report is still made.

| Area          | What it reads                                                                                                                                                                 |
| ------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Entra ID      | Tenant and directory sync, licences, security defaults, user and guest settings, cross-tenant access, Conditional Access and named locations, admin roles (active and PIM eligible), MFA registration, authentication methods, identity providers; MFA coverage (registered and phishing-resistant), emergency access accounts, dangling admins, role overlap, legacy authentication sign-ins, user consent settings, PIM role settings, the members of excluded and role-holding groups, access reviews, password hash sync |
| Threat protection | Risky users, risk detections (Identity Protection) and Microsoft Defender XDR incidents |
| Microsoft 365 | Domains, Microsoft Secure Score and its controls, SharePoint and OneDrive sharing, audit logging (Purview audit log search and the Entra audit log)                            |
| Applications  | App registrations and enterprise apps: expired, expiring and long-lived secrets and certificates; over-privileged permissions (Microsoft Graph application permissions and delegated consents, rated Critical, High, Medium); dangling redirect URIs (hosts looked up in DNS), wildcard and non-HTTPS URIs |
| Coverage      | Every lens, assessed or not and why (permission, licence, role); and what Microsoft Graph doesn't reach (Exchange Online, Defender for Office 365, Purview, Teams, Defender for Cloud Apps, Sentinel), with what would cover it |
| Intune        | Tenant settings, enrollment restrictions, compliance policies, endpoint security policies, managed devices (compliance, encryption, stale), Entra ID devices no MDM manages     |

The findings follow zero trust. Identity: MFA for everyone and for admins,
legacy authentication blocked, risk-based policies, privileged access.
Data: sharing, audit logging and Secure Score. Devices: compliance,
encryption, endpoint security and unmanaged devices. Each finding says what
to do and links to Microsoft's guidance.
