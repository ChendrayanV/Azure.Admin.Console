function Get-AACIntuneHuntingQuery {
    <#
    .SYNOPSIS
        The Intune hunting queries this module ships, in the shape
        ConvertFrom-AACHuntingQueryYaml returns.
    .DESCRIPTION
        The Azure-Sentinel repository has no hunting queries for the Intune
        tables, so these are the module's own. They need Intune's diagnostic
        settings to send logs to the workspace (Intune admin center, Reports,
        Diagnostics settings).

        The tables and columns are as Azure Monitor documents them. Microsoft
        doesn't document the values of OperationName and the like, so the
        filters are deliberately broad: tune them on real data.

        The IDs are fixed, so deploying again updates a query instead of
        adding another. No time filter: the Hunting page's time range applies.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param()

    @{
        Id          = '3f0c6a52-8d1e-4b7a-9c25-6e1d7a40b311'
        Name        = 'Intune - burst of device wipes, retires or deletes by one identity'
        Description = 'One identity running five or more destructive device actions in an hour. Can be a mass wipe from a compromised admin account. Tune the threshold and the operation names on your own logs.'
        Tactics     = @('Impact'); Techniques = @('T1485'); DataTypes = @('IntuneAuditLogs'); Version = '1.0.0'; MovedTo = ''
        Query       = @'
let threshold = 5;
IntuneAuditLogs
| where OperationName has_any ("wipe", "retire", "delete")
| summarize Actions = count(), Operations = make_set(OperationName, 10) by Identity, bin(TimeGenerated, 1h)
| where Actions >= threshold
| sort by Actions desc
'@
    }
    @{
        Id          = '7b2e94d1-0c3f-4e68-a1d7-52c8f6e3a902'
        Name        = 'Intune - compliance or configuration policy changes'
        Description = 'Who created, changed, assigned or deleted compliance and configuration policies. Weakening them is a way to get around device controls. Tune the operation names on your own logs.'
        Tactics     = @('DefenseEvasion'); Techniques = @('T1562'); DataTypes = @('IntuneAuditLogs'); Version = '1.0.0'; MovedTo = ''
        Query       = @'
IntuneAuditLogs
| where OperationName has_any ("policy", "compliance", "configuration")
| where OperationName has_any ("create", "update", "patch", "delete", "assign")
| project TimeGenerated, Identity, OperationName, ResultType, CorrelationId, Properties
| sort by TimeGenerated desc
'@
    }
    @{
        Id          = 'c41d7e08-5a96-4f23-8b6e-0d9a2f7c1e54'
        Name        = 'Intune - days with many failed enrollments'
        Description = 'Ten or more failed enrollment operations in a day. Can be a broken enrollment setup, or someone trying to enroll devices they should not. Tune the threshold on your own logs.'
        Tactics     = @('InitialAccess'); Techniques = @('T1078'); DataTypes = @('IntuneOperationalLogs'); Version = '1.0.0'; MovedTo = ''
        Query       = @'
let threshold = 10;
IntuneOperationalLogs
| where OperationName has "enrollment"
| where Result !~ "Success"
| summarize Failures = count() by OperationName, Result, bin(TimeGenerated, 1d)
| where Failures >= threshold
| sort by Failures desc
'@
    }
    @{
        Id          = '9ea85b36-2f71-4d0c-b3a4-81c6d5e09f27'
        Name        = 'Intune - jailbroken or non-compliant devices'
        Description = 'Devices whose latest Intune report says jailbroken or non-compliant, with their encryption state and owner. Sign-ins from these devices deserve a closer look.'
        Tactics     = @('DefenseEvasion'); Techniques = @(); DataTypes = @('IntuneDevices'); Version = '1.0.0'; MovedTo = ''
        Query       = @'
IntuneDevices
| summarize arg_max(TimeGenerated, *) by DeviceId
| where JailBroken =~ "True" or CompliantState =~ "Noncompliant"
| project TimeGenerated, DeviceName, UPN, OS, OSVersion, JailBroken, CompliantState, EncryptionStatusString, LastContact, Ownership
| sort by LastContact desc
'@
    }
}
