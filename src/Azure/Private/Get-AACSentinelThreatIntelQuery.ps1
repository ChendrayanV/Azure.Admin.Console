function Get-AACSentinelThreatIntelQuery {
    <#
    .SYNOPSIS
        The KQL queries behind Get-AACSentinelThreatIntelligence.
    .DESCRIPTION
        Sentinel keeps threat indicators in two tables: ThreatIntelIndicators
        (STIX, current) and ThreatIntelligenceIndicator (legacy, being
        retired). Both are queried, and whichever the workspace lacks fails
        with 'failed to resolve', which the caller treats as absent.

          stix, legacy                 per source and indicator type: how
                                       many, active, expired, expiring within
                                       -ExpiringDays, average and low
                                       confidence, last update
          stixList, legacyList         with -Indicator: the indicators
                                       themselves, newest first, at most
                                       -Limit from each table

        A record is written each time an indicator changes or is refreshed,
        so only each indicator's latest record within -Days counts. Indicator
        types are STIX observable names (ipv4-addr, domain-name, url, file,
        email-addr...); legacy rows get the same names from the column that
        holds their value.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [ValidateRange(1, 365)]
        [int] $Days = 30,

        [ValidateRange(1, 90)]
        [int] $ExpiringDays = 7,

        [ValidateRange(0, 100)]
        [int] $LowConfidence = 50,

        [switch] $Indicator,

        [ValidateRange(1, 500000)]
        [int] $Limit = 5000
    )

    $legacyType = "case(isnotempty(NetworkIP) or isnotempty(NetworkSourceIP) or isnotempty(NetworkDestinationIP), iff(coalesce(NetworkIP, NetworkSourceIP, NetworkDestinationIP) contains ':', 'ipv6-addr', 'ipv4-addr'), isnotempty(DomainName), 'domain-name', isnotempty(Url), 'url', isnotempty(FileHashValue), 'file', isnotempty(EmailSenderAddress), 'email-addr', 'other')"
    $queries = [ordered]@{}
    $queries['stix'] = @"
ThreatIntelIndicators
| where TimeGenerated > ago($($Days)d)
| summarize arg_max(TimeGenerated, *) by Id
| where tostring(IsDeleted) != 'true'
| extend IndicatorType = tostring(split(ObservableKey, ':')[0])
| summarize Indicators = count(), Active = countif(tostring(IsActive) == 'true' and (isnull(ValidUntil) or ValidUntil > now())), Expired = countif(isnotnull(ValidUntil) and ValidUntil <= now()), ExpiringSoon = countif(ValidUntil > now() and ValidUntil <= now() + $($ExpiringDays)d), AverageConfidence = avg(Confidence), LowConfidence = countif(Confidence < $LowConfidence), LastUpdated = max(LastUpdateTime) by Source = SourceSystem, IndicatorType
"@
    $queries['legacy'] = @"
ThreatIntelligenceIndicator
| where TimeGenerated > ago($($Days)d)
| summarize arg_max(TimeGenerated, *) by IndicatorId
| extend IndicatorType = $legacyType
| summarize Indicators = count(), Active = countif(Active == true and ExpirationDateTime > now()), Expired = countif(ExpirationDateTime <= now()), ExpiringSoon = countif(ExpirationDateTime > now() and ExpirationDateTime <= now() + $($ExpiringDays)d), AverageConfidence = avg(ConfidenceScore), LowConfidence = countif(ConfidenceScore < $LowConfidence), LastUpdated = max(TimeGenerated) by Source = SourceSystem, IndicatorType
"@
    if ($Indicator) {
        $queries['stixList'] = @"
ThreatIntelIndicators
| where TimeGenerated > ago($($Days)d)
| summarize arg_max(TimeGenerated, *) by Id
| where tostring(IsDeleted) != 'true'
| top $Limit by LastUpdateTime desc
| project Id, IndicatorType = tostring(split(ObservableKey, ':')[0]), Value = ObservableValue, Source = SourceSystem, Confidence, IsActive, ValidFrom, ValidUntil, LastUpdated = LastUpdateTime, Tags, Name = tostring(Data.name), Description = tostring(Data.description)
"@
        $queries['legacyList'] = @"
ThreatIntelligenceIndicator
| where TimeGenerated > ago($($Days)d)
| summarize arg_max(TimeGenerated, *) by IndicatorId
| top $Limit by TimeGenerated desc
| project Id = IndicatorId, IndicatorType = $legacyType, Value = coalesce(NetworkIP, NetworkSourceIP, NetworkDestinationIP, DomainName, Url, FileHashValue, EmailSenderAddress), Source = SourceSystem, Confidence = ConfidenceScore, IsActive = Active, ValidFrom = datetime(null), ValidUntil = ExpirationDateTime, LastUpdated = TimeGenerated, Tags, Name = ThreatType, Description
"@
    }
    $queries
}
