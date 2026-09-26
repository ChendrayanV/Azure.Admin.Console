# PDF export libraries - where they came from

The PDF reports (`Invoke-AACPester -PdfPath`, `Get-AACAdvisorRecommendation -PdfPath`, `Get-AACFirewallRule -PdfPath`) are rendered with
PDFsharp + MigraDoc. The assemblies here are copied unmodified from the
official nuget.org packages below (the `lib/net8.0` build of each), and are
loaded only when a PDF is exported - never at module import.

| Package (nuget.org) | Version | License | Files taken |
|---|---|---|---|
| PDFsharp | 6.2.4 | MIT (empira Software GmbH) | PdfSharp.dll, PdfSharp.Charting.dll, PdfSharp.Shared.dll, PdfSharp.System.dll |
| PDFsharp-MigraDoc | 6.2.4 | MIT (empira Software GmbH) | MigraDoc.DocumentObjectModel.dll, MigraDoc.Rendering.dll |
| Microsoft.Extensions.Logging.Abstractions | 8.0.3 | MIT (Microsoft) | Microsoft.Extensions.Logging.Abstractions.dll |
| Microsoft.Extensions.DependencyInjection.Abstractions | 8.0.2 | MIT (Microsoft) | Microsoft.Extensions.DependencyInjection.Abstractions.dll |

System.Security.Cryptography.Pkcs, the packages' other dependency, ships
with PowerShell itself and isn't vendored.

## How they were checked

1. Each `.nupkg` was downloaded from `https://api.nuget.org/v3-flatcontainer/`
   and passed `dotnet nuget verify --all`:
   - every package carries the nuget.org repository signature
     (`CN=NuGet.org Repository by Microsoft`, certificate SHA-256
     `1F4B311D9ACC115C8DC8018B5A49E00FCE6DA8E2855F9F014CA6F34570BC482D`);
   - the two Microsoft.Extensions packages also carry Microsoft's author
     signature (`CN=Microsoft Corporation`, certificate SHA-256
     `566A31882BE208BE4422F7CFD66ED09F5D4524A5994F50CCC8B05EC0528C1353`).
2. The two Microsoft.Extensions DLLs are also Authenticode-signed by
   Microsoft (`CN=.NET, O=Microsoft Corporation`). The PDFsharp and MigraDoc
   DLLs are not Authenticode-signed by their publisher, so the SHA-256 pins
   below are what vouches for them.

Package SHA-512 (base64) as downloaded:

| Package | SHA-512 |
|---|---|
| pdfsharp.6.2.4.nupkg | `K1/qaAyYQxf4g57OGAS21RxDbi5nAX4TrWjt8RBwdTC2NAwO8vPFeGC0sfc1LvQsFitepCXFs6CGhanA1NRfDg==` |
| pdfsharp-migradoc.6.2.4.nupkg | `Df9u3bMIYgfwRY+ggV0xG1tl9ib6Mnm/LEynnOGKN7GSD/KCMjlJMCwpX+CWyaYhyGjIU3cY0W8ig2JAZOtfGQ==` |
| microsoft.extensions.logging.abstractions.8.0.3.nupkg | `5onsHiy50vr6n9n2q4YaCJWqmhy8n7N+ndhWyNFwkATrFFXmRXC1EBO+iLYOmuDET4+FOTLZzeqzPdtC/OwZmw==` |
| microsoft.extensions.dependencyinjection.abstractions.8.0.2.nupkg | `uhlg7xEKxzh6Kgbu/ALFnOV7D+WLPgzMt5scjyFQEFxdH0tl4O2V/1DXDygUKRfGpzW4P05UBrsdj53R+WNdfQ==` |

## Integrity check at load time

`Private\Import-AACPdfLibrary.ps1` holds the SHA-256 of every DLL in this
folder and refuses to load any of them if a single hash differs (or a file
is missing) - so a swapped or tampered DLL is never executed. The pins live
in the module's code rather than in this folder, so replacing a DLL and a
checksum file together isn't enough to get past the check.

To upgrade: download the new packages, repeat the checks above, copy the
`lib/net8.0` DLLs here, and update the hashes in `Import-AACPdfLibrary.ps1`
and the tables in this file.
