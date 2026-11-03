# Azure DevOps assessment

[Guide index](../../GUIDE.md) · [Command reference](../Azure.Admin.Console.md)

**Commands:** [`Invoke-AACADOAssessment`](../Invoke-AACADOAssessment.md)

`Invoke-AACADOAssessment` (`Get-AACADOInventory` in 0.14 and earlier) assesses
one or more Azure DevOps organizations - read-only, through the Azure DevOps
REST API:

```powershell
$pat = Read-Host -Prompt 'Azure DevOps PAT' -AsSecureString
Invoke-AACADOAssessment -Organization contoso -PersonalAccessToken $pat                       # every project
Invoke-AACADOAssessment -Organization contoso -PersonalAccessToken $pat -HtmlPath .\ADO.html -PdfPath .\ADO.pdf -CsvPath .\ADO.csv
Invoke-AACADOAssessment -Organization contoso -PersonalAccessToken $pat -View Task -NoDisplay | Where-Object Kind -EQ 'CLI'
Invoke-AACADOAssessment -Organization contoso -PersonalAccessToken $pat -View ServiceConnection -NoDisplay | Where-Object OpenToAllPipelines
Invoke-AACADOAssessment -Organization contoso -Project Payments -PersonalAccessToken $pat -YamlPath .\pipelines -Skip Security, Metrics
Invoke-AACADOAssessment -DiscoverOrganization -UseAzureSignIn -IncludeAzure -HtmlPath .\ADO.html   # with Connect-AAC: every organization, no PAT
Invoke-AACADOAssessment -Organization contoso -PersonalAccessToken $pat -View SbomComponent -NoDisplay | Where-Object Component -EQ 'log4j-core'   # who ships it
```

- **SBOM:** which build pipelines produce a software bill of materials - the
  [Microsoft SBOM Tool](https://github.com/microsoft/sbom-tool) (`sbom-tool
  generate`, the Manifest Generator task, `GenerateSBOM=true` in a .NET
  project), 1ES Pipeline Templates, Syft, CycloneDX, Trivy or Docker - and
  which validate one (`sbom-tool validate`). From each one's **latest
  successful run**, the SBOM it published - the `_manifest/spdx_2.2` (or
  `spdx_3.0`) `manifest.spdx.json`, or any SPDX or CycloneDX JSON file in its
  artifacts: its format, the tool that made it, components and files,
  completeness against the NTIA minimum elements (name, version, supplier,
  package URL), licences by kind (permissive, weak or strong copyleft,
  unknown), and every component with its version, ecosystem, supplier and
  licence - so when a vulnerable package is announced, one filter says which
  pipelines ship it. Findings: pipelines that deploy or publish with no SBOM,
  an SBOM generated but not published, incomplete SBOMs, strong copyleft
  licences, SBOMs never validated. `-Skip Sbom` leaves the artifacts unread;
  reading them needs the token's Build (Read) scope.

- **Pipelines:** every build pipeline - **YAML**, or **classic** (built in
  the designer, with no YAML file: flagged) - and every classic release
  pipeline, with its last run, the repository's last push, the service
  connections, variable groups and environments it uses, and the Azure
  subscriptions it reaches.
- **How tools are found:** one catalogue of about 150 tools - each with its
  category, what it does and the regular expression that finds it - is matched
  against **every file a pipeline runs**:
  - its YAML and the templates it includes - local, or from another Azure
    Repos repository (`template@repo` through `resources: repositories`),
    nested to `-TemplateDepth` (3) - with comments, `displayName:` and
    `template:` lines left out;
  - the **script files** it calls (`filePath:` / `scriptPath:` inputs,
    `./deploy.sh`, `pwsh -File build.ps1`...) and the scripts those call, from
    the pipeline's repository (`-MaxScriptFiles`, 25 a pipeline);
  - the **package.json scripts** `npm run` / `yarn` / `pnpm` run (with their
    `pre`/`post` scripts) and the **Makefile targets** `make` runs;
  - a classic pipeline's tasks (mapped from task IDs to names);
  - **container images** (`ghcr.io/fluxcd/flux-cli:v2.3.0` is Flux, version
    v2.3.0).
- **Categories:** Lint, Build, Test, Security, Deploy, Publish, **GitOps**
  (Flux, Argo CD, Kustomize) and Tooling (az, git, jq, Node.js...). The
  findings - no linting, no tests, no security scanning - read them, for YAML
  and classic pipelines alike.
- **Report tabs for tools:**
  - **Tools** - one row per tool: category, pipelines, projects, the versions
    seen (an installer task such as `UseNode@1`, an image tag, or "agent
    default") and how it was found;
  - **Coverage** - per pipeline, Yes / No for each stage;
  - **Evidence** - every match: pipeline, tool, version, how it was found
    (task, inline script, script file, package.json, Makefile, image, classic
    task), file, line and the line itself, with credentials masked;
  - **Unrecognised** - commands scripts run that no rule knows, most-run
    first (a tool missing from the catalogue shows here), and the templates
    and script files that couldn't be read, with the reason (a path built from
    a variable, a GitHub repository...);
  - **Tasks** (`-View Task`) - every task with its major version and what it
    does, packages installed at a version (`npm install -g x@1.2`,
    `Install-Module -RequiredVersion`...), shells, containers, hosted images
    and pools.
- **Tools of your own:** `-ToolRule @(@{ Category = 'Deploy'; Tool = 'Acme
  Deployer'; Pattern = 'acme-deployer\s+push'; Purpose = 'Pushes a release' })`,
  or a team file with `-ToolRulePath .\rules.psd1`
  (`@{ Rules = @( @{ ... }, ... ) }`, or a JSON list).
- **Security posture:** service connections open to every pipeline, signing
  in with a client secret instead of workload identity federation, or
  unused; variable groups with secrets kept outside Key Vault, secret-looking
  variables not marked secret (names only - never values), or open to every
  pipeline; production environments with no approval, environments with no
  checks or open to every pipeline; default branches with no required
  reviewers or build validation; **GitHub Advanced Security for Azure
  DevOps** per repository (on, off) with its active alerts by type and
  severity.
- **Delivery metrics** over `-MetricDays` (30): each pipeline's runs, success
  rate (cancelled runs left out), average duration and queue time, runs a
  week; each environment's deployments, deployments a week and **change
  failure rate** (DORA).
- **Who to contact** (`-View Member`, the People tab): each project's
  **Project Administrators** (people, or groups in that group), its **team
  admins** and **team members** - one row per person with their roles and
  teams - and on each project row the first contacts (administrators, then
  team admins) with their e-mail. `-Skip Members` leaves them out.
- **Branching** (`-View Branch`, `-View BranchPolicy`): every branch with its
  role from its name (default, develop, release/\*, hotfix/\*, feature/\*,
  personal), last commit, ahead and behind the default branch, stale after
  `-StaleBranchDays` (90) and the policies on it; each repository's
  **branching strategy** - GitFlow, trunk-based with release branches,
  trunk-based / GitHub flow, feature branching or single branch - with its
  tags, open pull requests and Git LFS. Every **branch policy**, on or off,
  with its settings in words and its GitHub equivalent (rulesets, CODEOWNERS).
  `-Skip Branches` leaves the branches out.
- **DORA** (`-View Dora`, the DORA tab): per project and for the
  organization, the four keys over `-MetricDays` - deployment frequency, lead
  time (run queued to deployed), change failure rate and time to restore (a
  failed deployment to the next success) - from production environments and
  classic release stages (every environment when a project has none), each
  banded **Elite, High, Medium or Low**; overall is the weakest.
- **Moving to GitHub** (the Variables, Artifacts, Test plans, Agents and
  extensions and Migration tabs): every **variable** by name - pipeline
  settings, YAML and variable groups, secret or not, never values - with where
  it goes on GitHub; **Azure Artifacts** feeds and their packages, and whether
  GitHub Packages can hold them (npm, NuGet, Maven - not PyPI, Universal
  Packages or Cargo); **test plans** (no GitHub equivalent); agent pools and
  their agents; marketplace **extensions** and the pipelines whose tasks come
  from them; **Advanced Security settings** per repository and project;
  wikis and service hooks. `-View Migration` sums it up per project with rough
  effort points (classic pipelines, marketplace tasks, secrets, feeds, test
  plans, large or LFS repositories weigh most) and a complexity; `-View
  MigrationMap` says where each kind of thing lands on GitHub and the tool
  that moves it (GitHub Enterprise Importer, GitHub Actions Importer...).
  `-Skip Migration` leaves this data out; the PAT needs Packaging, Test
  Management, Wiki, Agent Pools and Extensions (Read).
- **One project at a time, in the HTML report:** a **Project** selector at the
  top filters every tab to the project chosen - its pipelines, tasks, tools'
  evidence, coverage, repositories, service connections, variable groups,
  environments and findings - and shows a card with the project's facts, who
  to contact, and how many rows each table has for it, each a link. Tiles and
  charts stay organization-wide; the tool matrix and the unrecognised list
  say they aren't by project.
- **Several organizations:** `-Organization contoso, fabrikam`, or
  `-DiscoverOrganization` for every organization your sign-in belongs to.
  Rows carry an Organization column.
- **Disabled repositories** are left out, with the pipelines that build
  them (the report says how many); their YAML is never read.
  `-IncludeDisabledRepository` lists them, each pipeline with a finding.
- **Progress:** each stage of the read, and the analysis, shows the
  projects done, the time left and the project being read.
- **Offline review:** `-YamlPath .\pipelines` saves every pipeline's YAML,
  the templates it includes, and each classic pipeline's steps (as JSON) -
  ready to review or diff.
- **Azure link:** `-IncludeAzure` (after `Connect-AAC`) follows each Azure
  service connection to its service principal and the Azure roles it holds,
  and flags pipeline identities that are Owner (or can grant access) or
  Contributor on a whole subscription.
- **Findings** also cover classic, stale, failing and disabled pipelines,
  deprecated or older task versions, unpinned container images, retired
  hosted images, a value that looks like a secret written into the YAML (its
  key and line - never the value), unreliable pipelines and long queues, and
  idle repositories.
- **Signing in:** `-PersonalAccessToken` (a SecureString; read scopes:
  Build, Code, Project and Team, Release, Service Connections, Variable
  Groups, Environment, Advanced Security, Identity), the `AZURE_DEVOPS_EXT_PAT`
  environment variable, or `-UseAzureSignIn` - your `Connect-AAC` sign-in,
  for organizations connected to your tenant. The token goes only to Azure
  DevOps and is never written anywhere.
- YAML in GitHub or another non-Azure Repos repository can't be read through
  Azure DevOps: the pipeline says so. `-Skip Yaml, Security, Metrics,
  AdvancedSecurity, Members` leaves parts out, to read faster.

`-View` returns (and writes to `-CsvPath`) Pipeline, Project, Repository,
Task, Tool, Evidence, Coverage, Unrecognised, ServiceConnection, VariableGroup,
Environment, Member or Finding rows;
`-HtmlPath` and `-PdfPath` write a report with a tab for each.
