function Get-AACPesterOutcomeCount {
    <#
    .SYNOPSIS
        Counts the passed, failed and skipped tests under a Pester v5 result
        node (a container, Describe or Context), including nested blocks.
    .DESCRIPTION
        Skipped and Inconclusive count as Skipped: neither tells you the check
        passed, and neither is a genuine failure. NotRun tests (left out by a
        -Tag/-TestName filter) aren't counted at all, so these numbers match
        the report's summary, which counts them separately.

        Walks the tree with an explicit stack rather than recursion, and reads
        Tests/Blocks through Get-AACPropertyValue because a container object
        has Blocks but no Tests of its own.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [object] $Node
    )

    $counts = @{ Passed = 0; Failed = 0; Skipped = 0 }
    $pending = [System.Collections.Generic.Stack[object]]::new()
    $pending.Push($Node)

    while ($pending.Count -gt 0) {
        $current = $pending.Pop()
        foreach ($test in (Get-AACPropertyValue -InputObject $current -Name 'Tests')) {
            switch ([string]$test.Result) {
                'Passed' { $counts.Passed++ }
                'Failed' { $counts.Failed++ }
                'NotRun' { }
                default { $counts.Skipped++ }
            }
        }
        foreach ($block in (Get-AACPropertyValue -InputObject $current -Name 'Blocks')) {
            $pending.Push($block)
        }
    }

    return $counts
}
