# Third-party notices

Azure.Admin.Console is MIT licensed (see [LICENSE](LICENSE)). It also ships material from these projects, under their own licences.

## Data

`src/Azure/Private/ServiceBaseline.json` is converted from the three projects below by `tools/Update-AACServiceBaseline.ps1`: fields selected and renamed, and disabled or hidden entries left out. `Get-AACAlertBaseline`, `Get-AACResiliencyRecommendation`, `Invoke-AACResiliencyAssessment`, `Invoke-AACLandingZoneAssessment` and `New-AACServiceBlueprint` read it. None of these projects is affiliated with or endorses this module.

### Azure Monitor Baseline Alerts (AMBA)

- Source: <https://github.com/Azure/azure-monitor-baseline-alerts/tree/ec5e5f3acfcdc52773110517b1f51bd06cf766de>
- Commit: `ec5e5f3acfcdc52773110517b1f51bd06cf766de`
- Used: alert names, severities, thresholds, windows, queries, descriptions and links

```text
MIT License

Copyright (c) Microsoft Corporation.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE
```

### Azure Proactive Resiliency Library v2 (APRL)

- Source: <https://github.com/Azure/Azure-Proactive-Resiliency-Library-v2/tree/e6aaa59a8e70e082255698692a97ad878c145de8>
- Commit: `e6aaa59a8e70e082255698692a97ad878c145de8`
- Used: recommendation names, impact, categories, descriptions, benefits, links and KQL queries

```text
MIT License

Copyright (c) Microsoft Corporation.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE
```

### Azure Landing Zone checklist queries

- Source: <https://github.com/martinopedal/alz-graph-queries/tree/58867cb377b492d9c0cf3527f572d48a3173ea47>
- Commit: `58867cb377b492d9c0cf3527f572d48a3173ea47`
- Used: checklist text, categories, severities and Resource Graph queries

```text
MIT License

Copyright (c) 2026 martinopedal

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Libraries

The vendored libraries in `lib/` keep their licence files beside them: `lib/Spectre.Console.LICENSE.md` for Spectre.Console, and `lib/pdf/` for PDFsharp, MigraDoc and the Microsoft.Extensions assemblies (see `lib/pdf/SOURCES.md`).
