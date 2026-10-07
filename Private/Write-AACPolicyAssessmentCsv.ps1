function Write-AACPolicyAssessmentCsv {
    <#
    .SYNOPSIS
        Writes Invoke-AACPolicyAssessment's tables to CSV files in a folder,
        and returns the files.
    .DESCRIPTION
        assignments, assignment-compliance (per assignment and
        subscription), policies (compliance per assignment and policy),
        initiative-policies (each assigned initiative's member policies,
        their effect, parameter values and compliance), categories, subscriptions, management-groups, initiatives,
        definitions, exemptions, role-assignments and findings. Empty tables
        are left out.
    #>
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Assessment,

        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }
    $write = {
        param([string] $File, [object[]] $Rows)
        if (-not @($Rows).Count) { return }
        $target = Join-Path -Path $Path -ChildPath "$File.csv"
        # The nested lists (an assignment's compliance...) have files of their own.
        $Rows | Select-Object -Property * -ExcludeProperty Compliance, PolicyStates, InitiativePolicies, Findings | Export-Csv -LiteralPath $target -NoTypeInformation -Encoding utf8
        Get-Item -LiteralPath $target
    }
    & $write 'assignments' $Assessment.Assignments
    & $write 'assignment-compliance' $Assessment.AssignmentCompliance
    & $write 'policies' $Assessment.Policies
    & $write 'initiative-policies' $Assessment.InitiativePolicies
    & $write 'categories' $Assessment.Categories
    & $write 'subscriptions' $Assessment.Subscriptions
    & $write 'management-groups' $Assessment.ManagementGroups
    & $write 'initiatives' $Assessment.Initiatives
    & $write 'definitions' $Assessment.Definitions
    & $write 'exemptions' $Assessment.Exemptions
    & $write 'role-assignments' $Assessment.Roles
    & $write 'findings' $Assessment.Findings
}
