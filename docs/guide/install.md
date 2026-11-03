# Install

[Guide index](../../GUIDE.md) · [Command reference](../Azure.Admin.Console.md)

```powershell
Install-PSResource -Name Azure.Admin.Console     # PSResourceGet
# or
Install-Module -Name Azure.Admin.Console -Scope CurrentUser
```

One module is installed with it: PSRule for Azure (PSRule.Rules.Azure 1.47
or later, with PSRule), for `Invoke-AACPSRule`. There are no Az or
Microsoft.Graph modules.

|                                   | Windows         | Linux / macOS                       |
| --------------------------------- | --------------- | ----------------------------------- |
| Console views, objects, CSV, HTML | PowerShell 7.2+ | PowerShell 7.2+                     |
| PDF reports                       | PowerShell 7.4+ | not supported (needs Windows fonts) |
