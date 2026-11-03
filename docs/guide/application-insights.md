# Application Insights

[Guide index](../../GUIDE.md) · [Command reference](../Azure.Admin.Console.md)

**Commands:** [`Invoke-AACApplicationInsightQuery`](../Invoke-AACApplicationInsightQuery.md)

`Invoke-AACApplicationInsightQuery` reads your application's exceptions, or
runs any KQL query. It works against a Log Analytics workspace
(`-LogWorkspaceName`, for workspace-based Application Insights, table
`AppExceptions`) or an Application Insights resource
(`-ApplicationInsightsName`, classic tables such as `exceptions`). The
resource is found by name with Resource Graph. The query runs through the Log
Analytics or Application Insights query API (`api.loganalytics.azure.com`,
`api.applicationinsights.io`). The token for that API comes from the
`Connect-AAC` sign-in, so there's no second sign-in and no Az module. It needs
Log Analytics Reader (or Reader). With an App Registration of your own
(`Connect-AAC -ClientId`), give it the delegated **Data.Read** permission of
the Log Analytics API and the Application Insights API.

A workspace only holds the exceptions of the Application Insights resources
that send to it. When a workspace has no exceptions, a warning says which
resources send there. If none do, it lists the ones you can see, where each
sends its data, and the `-ApplicationInsightsName` command to query one
directly. The portal's `exceptions | limit 5` runs in an Application Insights
resource, so it can show data that isn't in the workspace you queried.

```powershell
Invoke-AACApplicationInsightQuery -SubscriptionId '00000000-0000-0000-0000-000000000000' -LogWorkspaceName 'law-contoso-prod'
Invoke-AACApplicationInsightQuery -LogWorkspaceName 'law-contoso-prod' -Last 1d -MinimumSeverity Error -AppRoleName 'orders-api'
Invoke-AACApplicationInsightQuery -ApplicationInsightsName 'appi-contoso-portal' -ExceptionType '*SqlException' -Search 'timeout'
Invoke-AACApplicationInsightQuery -LogWorkspaceName 'law-contoso-prod' -Last 7d -HtmlPath .\Exceptions.html
Invoke-AACApplicationInsightQuery -ApplicationInsightsName 'appi-contoso-portal' -TableName requests -Last 15d
Invoke-AACApplicationInsightQuery -LogWorkspaceName 'law-contoso-prod' -TableName traces -MinimumSeverity Warning
Invoke-AACApplicationInsightQuery -LogWorkspaceName 'law-contoso-prod' -Query 'AppRequests | where Success == false | summarize count() by Name'
```

| Parameter          | Default      |                                                                                                                                                                                                                                                                 |
| ------------------ | ------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `-TableName`       | `exceptions` | The table to read: `requests`, `dependencies`, `traces`, `customEvents`, `pageViews`, `availabilityResults` and so on. Either schema's name works for either source (`requests` or `AppRequests`), and Tab completes them. A workspace's other tables work too. |
| `-Last`            | `2h`         | How far back: `30m`, `2h`, `7d` and so on. It also bounds `-Query`.                                                                                                                                                                                             |
| `-MinimumSeverity` | all          | `Verbose`, `Information`, `Warning`, `Error` or `Critical`, and worse. For exceptions and traces.                                                                                                                                                               |
| `-ExceptionType`   | all          | Exception types; wildcards work (`'*SqlException'`). For exceptions.                                                                                                                                                                                            |
| `-AppRoleName`     | all          | Apps or cloud roles.                                                                                                                                                                                                                                            |
| `-Search`          | none         | Text in the type or messages; with `-TableName`, in any column.                                                                                                                                                                                                 |
| `-Top`             | all          | The newest this many. By default every row in the period is read, up to the query API's limit of 500,000, and the view pages through them all.                                                                                                                  |
| `-Query`           |              | Any KQL instead of the exceptions query; its columns become the objects' properties.                                                                                                                                                                            |

The values you give are escaped before they go into the KQL.

Each exception is flattened into one object, the same from either table:

- **When and how bad:** time (UTC) and severity.
- **What:** type and message, plus the outer and innermost exception.
- **The `details` array:** the first entry's type, message and severity
  level, the number of entries, and the top stack frame (method, file and
  line).
- **Where it came from:** method, assembly, problem ID, operation name and
  ID, app/role, role instance, app version, client country and city.
- **Sampling and extras:** item count (for sampled telemetry) and custom
  properties.

The console view has tiles, a timeline of exceptions, a severity breakdown,
the top exception types, the top problems (a type thrown from one place) and
every exception, newest first. `-CsvPath` and `-HtmlPath` export them. With
`-TableName`, the view is a table of every row, with the table's most useful
columns first, for example time, name, result code, success and duration for
`requests`. The objects have all the columns.

If the table doesn't exist, the error panel says so and names the tables the
source does have. The closest names come first, then how many rows each has
in the period:

```text
There is no table 'request' in appi-contoso-portal.
Fix  Did you mean 'requests'? Tables in appi-contoso-portal with data in the
     last 15d: dependencies (40,211), requests (18,204), traces (9,120),
     exceptions (57). No data: availabilityResults, customEvents, ...
```
