function Invoke-AACTerraformCli {
    <#
    .SYNOPSIS
        Runs the terraform CLI once in a folder and returns its exit code and
        output - Export-AACTerraform -Plan's init, validate, plan and show.
    .DESCRIPTION
        Started directly (System.Diagnostics.Process), not through
        Start-Process: the output is read back, nothing opens a window, and
        the arguments are passed one by one, so a path with spaces needs no
        quoting. -Environment adds variables for this run only
        (TF_IN_AUTOMATION, ARM_SUBSCRIPTION_ID). Past -TimeoutMinutes the
        process is stopped and ExitCode is -1.

        Returns @{ ExitCode; Output (standard output); Error (standard
        error) }.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [string] $FilePath,

        [Parameter(Mandatory)]
        [string[]] $Argument,

        [Parameter(Mandatory)]
        [string] $WorkingDirectory,

        [System.Collections.IDictionary] $Environment = @{},

        [ValidateRange(1, 120)]
        [int] $TimeoutMinutes = 15
    )

    $start = [System.Diagnostics.ProcessStartInfo]::new($FilePath)
    foreach ($item in $Argument) { $start.ArgumentList.Add($item) }
    $start.WorkingDirectory = $WorkingDirectory
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($key in $Environment.Keys) { $start.Environment[[string]$key] = [string]$Environment[$key] }

    $process = [System.Diagnostics.Process]::Start($start)
    try {
        # Both streams read at once: a full stderr buffer would otherwise stall a chatty plan.
        $output = $process.StandardOutput.ReadToEndAsync()
        $errorText = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutMinutes * 60000)) {
            $process.Kill($true)
            return @{ ExitCode = -1; Output = ''; Error = "terraform $($Argument[0]) didn't finish within $TimeoutMinutes minute(s)." }
        }
        $process.WaitForExit()
        @{ ExitCode = $process.ExitCode; Output = $output.Result; Error = $errorText.Result }
    }
    finally { $process.Dispose() }
}
