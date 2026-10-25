---
document type: cmdlet
external help file: Azure.Admin.Console-help.xml
HelpUri: https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACADOInventory.md
Locale: en-US
Module Name: Azure.Admin.Console
PlatyPS schema version: 2024-05-01
title: Get-AACADOInventory
---

# Get-AACADOInventory

## SYNOPSIS

Inventories one or more Azure DevOps organizations - projects, pipelines (YAML, or classic with no YAML file - flagged) with their last run and delivery metrics, every task and tool they use (with versions), repositories, service connections, variable groups and environments with their security posture - as a Spectre.Console view, objects, and CSV, HTML and PDF reports.

## SYNTAX

### __AllParameterSets

```
Get-AACADOInventory [[-Organization] <string[]>] [[-Project] <string[]>] [[-PipelineId] <int[]>]
 [[-PersonalAccessToken] <securestring>] [[-Skip] <string[]>] [[-MetricDays] <int>]
 [[-TemplateDepth] <int>] [[-StaleDays] <int>] [[-InactiveDays] <int>] [[-StaleBranchDays] <int>]
 [[-ToolRule] <Object[]>] [[-ToolRulePath] <string>] [[-MaxScriptFiles] <int>]
 [[-YamlPath] <string>] [[-View] <string>] [[-ThrottleLimit] <int>] [[-CsvPath] <string>]
 [[-HtmlPath] <string>] [[-PdfPath] <string>] [[-Title] <string>] [-DiscoverOrganization]
 [-UseAzureSignIn] [-SkipYaml] [-IncludeAzure] [-IncludeDisabledRepository] [-PassThru] [-NoDisplay]
 [-NoPaging]
```

## ALIASES

This command has no aliases.

## DESCRIPTION

Read-only, through the Azure DevOps REST API - nothing is changed.
For each organization (-Organization, or -DiscoverOrganization) and
project (or -Project), it reads:

```text
  pipelines     every build pipeline: YAML or classic (designer,
                no YAML file), its folder, repository, state and
                last run, and every classic release pipeline
  steps         YAML pipelines' files from their default branch
                (Azure Repos Git) and the templates they include -
                local or template@repository, nested to
                -TemplateDepth; the script files, package.json
                scripts and Makefile targets they run (from the
                pipeline's repository); classic pipelines' tasks,
                named through the organization's task catalogue
  repositories  the last push, the branch policies on the default
                branch, GitHub Advanced Security for Azure DevOps
                (on or off, and active alerts by type and severity)
  security      service connections, variable groups and
                environments: who may use them, their checks
  runs          the runs of the last -MetricDays and each
                environment's deployments
```

Tools: one catalogue (about 150 tools) is matched against every file
a pipeline runs - its YAML and templates, script files, package.json
scripts, Makefile targets, a classic pipeline's tasks - and against
container images (fluxcd/flux-cli...). Categories: Lint, Build,
Test, Security, Deploy, Publish, GitOps (Flux, Argo CD,
Kustomize...) and Tooling (az, git, jq...). Every match is evidence
(-View Evidence): the pipeline, the tool, its version (an installer
task, an image tag), how it was found, the file and line, and the
line itself (credentials masked). -View Tool is the matrix of tools
with their pipelines, projects and versions; -View Coverage which
stages each pipeline has; -View Unrecognised the commands scripts
run that no rule knows (most-run first) and the templates and files
that couldn't be read. -ToolRule and -ToolRulePath add tools of
your own.

Tasks (-View Task): every task with its major version and what it
does (the task catalogue's description), packages installed at a
version, shells, container images, agent images and pools.

Findings: classic pipelines; never run, not run in -StaleDays, last
run failed, disabled; no security scanning, no tests, no linting;
deprecated or older task versions; unpinned container images;
retired hosted images; a value that looks like a secret written in
the YAML (its key and line - never the value); unreliable pipelines
and long queues; service connections open to every pipeline, using a
client secret rather than workload identity federation, or unused;
variable groups with secrets outside Key Vault, secret-looking
values not marked secret, open to every pipeline; production
environments with no approval, environments with no checks or open
to every pipeline; default branches with no required reviewers or
build validation; Advanced Security off, exposed secrets, critical
and high alerts; idle repositories.

Delivery metrics over -MetricDays: each pipeline's runs, success
rate (cancelled runs left out), average duration and queue time,
runs a week; each environment's deployments, deployments a week,
and change failure rate (DORA).

Branching: every branch with its role (from its name - develop,
release/\*, hotfix/\*, feature/\*...), last commit, ahead and behind the
default branch, stale after -StaleBranchDays, and the policies on it;
each repository's strategy (GitFlow, trunk-based with release
branches, trunk-based / GitHub flow, feature branching, single
branch). Every branch policy, on or off, with its settings in words
and its GitHub equivalent (rulesets, CODEOWNERS).

DORA, per project and for the organization: deployment frequency,
lead time (run queued to deployed), change failure rate and time to
restore, from production environments and classic release stages
(every environment when a project has no production one), each
banded Elite, High, Medium or Low; overall is the weakest.

Moving to GitHub: variables by name (pipeline settings, YAML,
variable groups - secret or not, never values), Azure Artifacts feeds
and their packages (and whether GitHub Packages can hold them), test
plans, wikis, service hooks, open pull requests, Git LFS, agent pools
and agents, marketplace extensions and the tasks pipelines use from
them, Advanced Security settings per repository and project; a
summary per project with rough effort points and a map of where each
kind of thing lands on GitHub and the tool that moves it.

-IncludeAzure (with Connect-AAC) follows each Azure service
connection to its service principal and the Azure roles it holds,
and flags pipeline identities that are Owner (or can grant access),
or Contributor on a whole subscription.

Signing in, in this order:

```text
  -PersonalAccessToken   a PAT with read scopes: Build, Code,
                         Project and Team, Release, Service
                         Connections, Variable Groups, Environment,
                         Advanced Security, Packaging, Test
                         Management, Wiki, Agent Pools, Extensions
  AZURE_DEVOPS_EXT_PAT   the same, from the environment (the
                         variable the Azure DevOps CLI reads)
  -UseAzureSignIn        your Connect-AAC sign-in (Microsoft Entra
                         ID), for organizations connected to your
                         tenant - no PAT to create or rotate
```

The token is sent only to Azure DevOps and never written anywhere.

## EXAMPLES

### Example 1

```powershell
$pat = Read-Host -Prompt 'Azure DevOps PAT' -AsSecureString
Get-AACADOInventory -Organization contoso -PersonalAccessToken $pat
```

Every project, pipeline and repository of the organization, with its tools, security posture and findings.

### Example 2

```powershell
Get-AACADOInventory -Organization contoso -PersonalAccessToken $pat -HtmlPath .\ADO.html -PdfPath .\ADO.pdf -CsvPath .\ADO.csv
```

The same as reports.

### Example 3

```powershell
Get-AACADOInventory -Organization contoso -PersonalAccessToken $pat -View Task -NoDisplay | Where-Object Kind -EQ 'CLI' | Group-Object -Property Name, Version
```

Every command-line tool the pipelines run, and the versions they set.

### Example 4

```powershell
Get-AACADOInventory -Organization contoso -PersonalAccessToken $pat -View ServiceConnection -NoDisplay | Where-Object OpenToAllPipelines
```

Service connections any pipeline can use.

### Example 5

```powershell
Connect-AAC
Get-AACADOInventory -DiscoverOrganization -UseAzureSignIn -IncludeAzure -HtmlPath .\ADO.html
```

Every organization you belong to, with each Azure service connection's roles in Azure.

### Example 6

```powershell
Get-AACADOInventory -Organization contoso -PersonalAccessToken $pat -View Migration -NoDisplay | Sort-Object -Property Effort -Descending
```

Projects by how much work the move to GitHub is.

### Example 7

```powershell
Get-AACADOInventory -Organization contoso -Project Payments -PersonalAccessToken $pat -YamlPath .\pipelines -Skip Security, Metrics
```

Save the project's pipelines and templates to a folder, to review or diff offline.

## PARAMETERS

### -CsvPath

Write the -View rows to this CSV file.

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 16
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -DiscoverOrganization

Add every organization the signed-in account is a member of (best
with -UseAzureSignIn, or a PAT for all accessible organizations).

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -HtmlPath

Write an interactive HTML report.

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 17
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -InactiveDays

A repository with no push in this many days is flagged (180 if not
given).

```yaml
Type: System.Int32
DefaultValue: 180
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 8
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -IncludeAzure

Link Azure service connections to their service principals' Azure
role assignments (needs Connect-AAC, Microsoft Graph read access to
service principals, and Reader on the scopes).

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -IncludeDisabledRepository

List disabled repositories, and the pipelines that build them (with a
finding each). By default both are left out, and the report says how
many; a disabled repository's YAML is never read.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -MaxScriptFiles

At most this many script files, package.json and Makefiles are read
for one pipeline (25 if not given; 0 reads none).

```yaml
Type: System.Int32
DefaultValue: 25
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 12
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -MetricDays

The days of run history the delivery metrics cover (30 if not
given; 1 to 365).

```yaml
Type: System.Int32
DefaultValue: 30
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 5
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -NoDisplay

Return the rows without showing the view.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -NoPaging

Show the whole view at once.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Organization

One or more organizations: a name (contoso) or a URL
(https://dev.azure.com/contoso or https://contoso.visualstudio.com).

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 0
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -PassThru

Show the view and also return the rows.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -PdfPath

Write a PDF report.

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 18
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -PersonalAccessToken

A personal access token, as a SecureString (Read-Host -AsSecureString).

```yaml
Type: System.Security.SecureString
DefaultValue: None
SupportsWildcards: false
Aliases:
- PAT
ParameterSets:
- Name: (All)
  Position: 3
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -PipelineId

Only these build pipelines (definition IDs) - with -Project, as IDs
are per project. Classic releases are then left out.

```yaml
Type: System.Int32[]
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 2
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Project

Only these projects, by name or ID.

```yaml
Type: System.String[]
DefaultValue: None
SupportsWildcards: false
Aliases:
- ProjectId
ParameterSets:
- Name: (All)
  Position: 1
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Skip

Leave parts out, to read faster: Yaml (no YAML files or templates),
Security (no service connections, variable groups, environments or
branch policies), Metrics (no run history or deployments),
AdvancedSecurity, Members (no Project Administrators or teams - who
to contact), Branches (no branches, tags or branching strategy),
Migration (no feeds, test plans, wikis, pull requests, agent pools,
service hooks or extensions - the move-to-GitHub data).

```yaml
Type: System.String[]
DefaultValue: '@()'
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 4
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -SkipYaml

The same as -Skip Yaml.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -StaleBranchDays

A branch (not the default one) with no commit in this many days is
stale (90 if not given).

```yaml
Type: System.Int32
DefaultValue: 90
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 9
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -StaleDays

A pipeline not run in this many days is flagged (90 if not given).

```yaml
Type: System.Int32
DefaultValue: 90
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 7
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -TemplateDepth

How deep included templates are followed (3 if not given; 0 reads
none).

```yaml
Type: System.Int32
DefaultValue: 3
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 6
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ThrottleLimit

How many requests run at once (1 to 32; 8 by default).

```yaml
Type: System.Int32
DefaultValue: 8
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 15
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -Title

The reports' title.

```yaml
Type: System.String
DefaultValue: "'Azure DevOps inventory'"
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 19
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ToolRule

Tools of your own to look for: @(@{ Category = 'Security'; Tool =
'Acme Scan'; Pattern = 'acme-scan' }). Category is Lint, Build, Test,
Security, Deploy, Publish, GitOps or Tooling; Pattern a regular
expression, matched ignoring case; Purpose (optional) says what the
tool does.

```yaml
Type: System.Object[]
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 10
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -ToolRulePath

A .psd1 or .json file of rules in the -ToolRule shape - a list of
@{ Category; Tool; Pattern; Purpose } - so a team keeps its own tools
in a file. Added to -ToolRule.

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 11
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -UseAzureSignIn

Use the Connect-AAC sign-in instead of a PAT.

```yaml
Type: System.Management.Automation.SwitchParameter
DefaultValue: False
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: Named
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -View

What is returned and written to -CsvPath: Pipeline (default),
Project, Repository, Task, Tool, Evidence, Coverage, Unrecognised,
ServiceConnection, VariableGroup, Environment, Member (who to contact),
Branch, BranchPolicy, Variable, Dora, Feed, TestPlan, AgentPool,
Extension, Migration, MigrationMap or Finding.

```yaml
Type: System.String
DefaultValue: "'Pipeline'"
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 14
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### -YamlPath

Save every pipeline's YAML (and the templates it includes), and each
classic pipeline's steps as JSON, under this folder - for offline
review and diffs.

```yaml
Type: System.String
DefaultValue: None
SupportsWildcards: false
Aliases: []
ParameterSets:
- Name: (All)
  Position: 13
  IsRequired: false
  ValueFromPipeline: false
  ValueFromPipelineByPropertyName: false
  ValueFromRemainingArguments: false
DontShow: false
AcceptedValues: []
HelpMessage: ''
```

### CommonParameters

This cmdlet supports the common parameters: -Debug, -ErrorAction, -ErrorVariable,
-InformationAction, -InformationVariable, -OutBuffer, -OutVariable, -PipelineVariable,
-ProgressAction, -Verbose, -WarningAction, and -WarningVariable. For more information, see
[about_CommonParameters](https://go.microsoft.com/fwlink/?LinkID=113216).

## INPUTS

## OUTPUTS

### AAC.DevOpsPipeline, AAC.DevOpsProject, AAC.DevOpsRepository, AAC.DevOpsTask, AAC.DevOpsToolUsage, AAC.DevOpsServiceConnection, AAC.DevOpsVariableGroup, AAC.DevOpsEnvironment, AAC.DevOpsMember, AAC.DevOpsToolEvidence, AAC.DevOpsCoverage, AAC.DevOpsUnrecognised, AAC.DevOpsBranch, AAC.DevOpsBranchPolicy, AAC.DevOpsVariable, AAC.DevOpsDora, AAC.DevOpsFeed, AAC.DevOpsTestPlan, AAC.DevOpsAgentPool, AAC.DevOpsExtension, AAC.DevOpsMigration, AAC.DevOpsMigrationMap or AAC.DevOpsFinding, by -View (piped onward, or with -PassThru or -NoDisplay)

## NOTES

## RELATED LINKS

- [Online version](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/Get-AACADOInventory.md)
- [about_Azure.Admin.Console](https://github.com/ChendrayanV/Azure.Admin.Console/blob/main/docs/about_Azure.Admin.Console.md)
