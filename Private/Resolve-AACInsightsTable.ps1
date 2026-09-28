function Resolve-AACInsightsTable {
    <#
    .SYNOPSIS
        Turns a -TableName into the table to query for a workspace or an
        Application Insights resource, with its time column and the columns
        worth showing first.
    .DESCRIPTION
        Application Insights tables have two names: the resource's classic
        one (requests, traces, ...) and the workspace's (AppRequests,
        AppTraces, ...). Either name works for either kind - 'requests' on a
        workspace is AppRequests, 'AppTraces' on a resource is traces. Any
        other name (a workspace's own tables, e.g. ContainerLog) is used as
        it is, with TimeGenerated as its time column.

        Returns Name, Time (the time column), IsExceptions, HasSeverity,
        IsKnown (an Application Insights table) and Columns (the columns the
        console view shows first).
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Workspace', 'Component')]
        [string] $Kind,

        [Parameter(Mandatory)]
        [string] $TableName
    )

    # classic name, workspace name, columns to show first (classic; workspace)
    $known = @(
        , @('requests', 'AppRequests', 'timestamp,name,resultCode,success,duration,cloud_RoleName,operation_Id', 'TimeGenerated,Name,ResultCode,Success,DurationMs,AppRoleName,OperationId')
        , @('dependencies', 'AppDependencies', 'timestamp,type,target,name,resultCode,success,duration,cloud_RoleName', 'TimeGenerated,DependencyType,Target,Name,ResultCode,Success,DurationMs,AppRoleName')
        , @('exceptions', 'AppExceptions', '', '')
        , @('traces', 'AppTraces', 'timestamp,severityLevel,message,cloud_RoleName,operation_Name', 'TimeGenerated,SeverityLevel,Message,AppRoleName,OperationName')
        , @('customEvents', 'AppEvents', 'timestamp,name,cloud_RoleName,operation_Name,user_Id', 'TimeGenerated,Name,AppRoleName,OperationName,UserId')
        , @('pageViews', 'AppPageViews', 'timestamp,name,url,duration,client_City,client_Browser', 'TimeGenerated,Name,Url,DurationMs,ClientCity,ClientBrowser')
        , @('availabilityResults', 'AppAvailabilityResults', 'timestamp,name,location,success,duration,message', 'TimeGenerated,Name,Location,Success,DurationMs,Message')
        , @('performanceCounters', 'AppPerformanceCounters', 'timestamp,category,counter,instance,value,cloud_RoleName', 'TimeGenerated,Category,Name,Instance,Value,AppRoleName')
        , @('customMetrics', 'AppMetrics', 'timestamp,name,value,valueCount,valueSum,cloud_RoleName', 'TimeGenerated,Name,Sum,ItemCount,Min,Max,AppRoleName')
        , @('browserTimings', 'AppBrowserTimings', 'timestamp,name,url,totalDuration,networkDuration,client_City', 'TimeGenerated,Name,Url,TotalDurationMs,NetworkDurationMs,ClientCity')
    )
    $match = $known | Where-Object { $TableName -in $_[0], $_[1] } | Select-Object -First 1
    $isWorkspace = $Kind -eq 'Workspace'
    if ($match) {
        [pscustomobject]@{
            Name         = if ($isWorkspace) { $match[1] } else { $match[0] }
            Time         = if ($isWorkspace) { 'TimeGenerated' } else { 'timestamp' }
            IsExceptions = $match[0] -eq 'exceptions'
            HasSeverity  = $match[0] -in 'exceptions', 'traces'
            IsKnown      = $true
            Columns      = @(($(if ($isWorkspace) { $match[3] } else { $match[2] })) -split ',' | Where-Object { $_ })
        }
    }
    else {
        [pscustomobject]@{
            Name         = $TableName
            Time         = if ($isWorkspace) { 'TimeGenerated' } else { 'timestamp' }
            IsExceptions = $false
            HasSeverity  = $false
            IsKnown      = $false
            Columns      = @()
        }
    }
}
