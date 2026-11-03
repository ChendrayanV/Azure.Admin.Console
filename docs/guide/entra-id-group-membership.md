# Entra ID group membership

[Guide index](../../GUIDE.md) · [Command reference](../Azure.Admin.Console.md)

**Commands:** [`Get-AACEntraGroupMembership`](../Get-AACEntraGroupMembership.md)

`Get-AACEntraGroupMembership` reads Entra ID groups and their members from
Microsoft Graph and follows nested groups to the end:

```powershell
Get-AACEntraGroupMembership -GroupName 'grp-finance', 'grp-hr'            # these groups, by exact name
Get-AACEntraGroupMembership -GroupNameStartsWith 'grp-azure-'             # every group whose name starts with this
Get-AACEntraGroupMembership                                                # every group in the tenant
Get-AACEntraGroupMembership -GroupNameStartsWith 'grp-' -HtmlPath .\Groups.html -CsvPath .\Groups.csv -PdfPath .\Groups.pdf
Get-AACEntraGroupMembership -GroupNameStartsWith 'grp-' -NoDisplay | Where-Object UserType -EQ 'Guest'   # the guests, and through which group
```

```text
-- grp-finance ---------------------------------------------------------------
  Type        Security  Created  2024-01-15 09:30 UTC
  Source      Cloud     Owners   Ada Lovelace (ada@contoso.example); app-payroll (Service principal)
  Membership  Assigned  Members  3 direct - 1 nested group - 4 in all (1 guest, 1 disabled)

  DIRECT MEMBERS (3)
    Member             Type           Account
    Ada Lovelace       User           ada@contoso.example
    Gus Guest          User           gus_fabrikam.example#EXT#@contoso.example   GUEST
    grp-finance-emea   Nested group   its members are listed below

  NESTED GROUP grp-finance-emea (3 members)
    Member             Type                Account
    Ada Lovelace       User                ada@contoso.example
    app-payroll        Service principal
    Grace Hopper       User                grace@contoso.example   DISABLED
```

The **HTML report** opens on the same structure as a tree: every group with
its details and counts, opening to its owners, its direct members and its
nested groups, each nested group opening to its own members (a report of a
few groups opens all the way). Its tabs hold the groups, **Members** -
everyone in each group once, marked Direct, Nested or Direct and nested,
with the nested groups they come through - and every membership row. The
**PDF** gives each group a page: its details, then its direct members, then
each nested group's members.

**One row per group and member** (`AAC.EntraGroupMember`), the same in the
objects, HTML, PDF and `-CsvLayout Member` CSV: the group (name, type - Microsoft 365, Security,
Mail-enabled security, Distribution, dynamic, role-assignable - whether
it's cloud or synced from on-premises AD, its membership type - Assigned or
Dynamic - when it was created, and its owners), the member (name, type - user,
group, device, service principal, contact - user principal name, mail,
member or guest, enabled or disabled, job title, department), and how it's
in the group: **Direct**, **Nested** (with **Via**, the path of nested
groups, and the depth), or **Empty** for a group with no members, so every
group appears. A group met again on its own path (a loop) is listed but not
followed twice. The console and reports also show each group's totals:
direct members, nested groups, and unique users, guests and disabled
accounts at every level.

**The CSV** is one row per group by default - the same file
[Export-EntraGroupMemberShip.ps1](https://www.powershellgallery.com/packages/Export-EntraGroupMemberShip)
writes, with the same columns and labels: GroupName, GroupSource (Cloud or
Windows Server AD), GroupType (`Security`, `Microsoft 365 / Dynamic`,
`Mail-Enabled Security / Role-Assignable` ...), Members (everyone in the
group, flattened: direct members and the members of every nested group at
any depth, each once, or `(No members)`) and NestedGroupMembers (every
nested group at any depth, by its path, with its own members:
`grp-finance-emea: Grace Hopper, Ada Lovelace; grp-finance-emea > grp-emea-audit: Linus Torvalds`),
then Owners (`Ada Lovelace (ada@contoso.example); app-payroll (Service principal)`
or `(No owners)`), CreatedDateTime (UTC) and MembershipType (Assigned,
Dynamic).
Service principals are listed with the other members.
A group whose members can't be read is left out of it, with a warning.
`-CsvLayout Member` writes the one-row-per-member rows instead.

**Sign-in.** It uses your `Connect-AAC` sign-in - no second prompt: a
Microsoft Graph token is taken from it silently, the way Application
Insights gets its Log Analytics token.

- Your account needs to be allowed to read groups in Entra ID, which members
  of the tenant are by default (guests, or tenants that restrict it, may
  not be).
- With an App Registration of your own (`Connect-AAC -ClientId`), give it
  Microsoft Graph's delegated **Group.Read.All** and **User.Read.All**
  permissions.
- Reads run 8 at a time, a level of nesting at a time, each group read
  once however many groups it's nested in; throttling waits as Graph asks.
  A group whose members can't be read is reported, and the rest carry on.

`-CsvPath` (alias `-OutputPath`) writes the rows; with no export parameter
the command shows the console view, as every command does.
