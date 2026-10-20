function Write-AACResourceMapPdf {
    <#
    .SYNOPSIS
        Writes a map (ConvertTo-AACResourceMap and friends) as a one-page
        PDF: the title and what was read, the whole diagram at full size and
        its legend, on a page sized to fit - vector, so it stays sharp at any
        zoom.
    .DESCRIPTION
        The map page (Private\ResourceMap.html) has a print mode; Microsoft
        Edge or Google Chrome prints it headless. PDFsharp can't draw SVG,
        and the browser is what lays the map out anyway. A browser of its own
        (a fresh profile in a temporary folder) so one you have open doesn't
        get in the way.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Map,

        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $Title,

        [string[]] $Fact = @(),

        [ValidateSet('RIGHT', 'DOWN')]
        [string] $Direction = 'RIGHT',

        [ValidateSet('dark', 'light', 'blueprint')]
        [string] $Theme = 'light',

        [ValidateSet('layered', 'hubspoke', 'packed')]
        [string] $Layout = 'layered',

        [ValidateSet('layered', 'packed')]
        [string] $Hierarchy = 'layered',

        # How long the browser gets to lay out and print the map.
        [int] $TimeoutSeconds = 120
    )

    $browser = Get-AACBrowserPath
    if (-not $browser) {
        throw 'Azure Admin Console needs Microsoft Edge or Google Chrome to write the diagram as a PDF, and found neither. Install one, or use -HtmlPath and print the page to PDF from your browser.'
    }

    $work = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ('aac-pdf-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $work -Force
    try {
        $page = Join-Path -Path $work -ChildPath 'map.html'
        $pdf = Join-Path -Path $work -ChildPath 'map.pdf'
        Write-AACResourceMapHtml -Map $Map -Path $page -Title $Title -Fact $Fact -Direction $Direction -Theme $Theme -Layout $Layout -Hierarchy $Hierarchy -Print
        # Each argument quoted whole: the temporary folder may have spaces in it.
        # The virtual time budget lets the page lay the map out before it's printed.
        $arguments = @(
            '--headless=new', '--disable-gpu', '--no-first-run', '--no-default-browser-check', '--disable-extensions', '--hide-scrollbars'
            "`"--user-data-dir=$(Join-Path -Path $work -ChildPath 'profile')`""
            '--no-pdf-header-footer', '--run-all-compositor-stages-before-draw', '--virtual-time-budget=60000'
            "`"--print-to-pdf=$pdf`""
            "`"$(([System.Uri]::new($page)).AbsoluteUri)`""
        ) -join ' '
        # Started directly rather than with Start-Process: no window, and nothing
        # that wraps Start-Process (a demo, a test) gets in the way.
        $start = [System.Diagnostics.ProcessStartInfo]::new($browser, $arguments)
        $start.UseShellExecute = $false
        $start.CreateNoWindow = $true
        $process = [System.Diagnostics.Process]::Start($start)
        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
        $written = $false
        # The browser may hand off to a child process: wait for the PDF itself,
        # whole (it can be opened on its own) rather than for the process.
        while (-not $written -and (Get-Date) -lt $deadline) {
            Start-Sleep -Milliseconds 400
            if ((Test-Path -LiteralPath $pdf) -and (Get-Item -LiteralPath $pdf).Length -gt 0 -and $process.HasExited) {
                try {
                    [System.IO.File]::Open($pdf, 'Open', 'Read', 'None').Dispose()
                    $written = $true
                }
                catch {
                    $written = $false
                }
            }
        }
        if (-not $process.HasExited) { $process | Stop-Process -Force -ErrorAction SilentlyContinue }
        if (-not $written) {
            throw "Azure Admin Console: the browser didn't write the PDF within $TimeoutSeconds seconds. Try again, or use -HtmlPath and print the page to PDF from your browser."
        }
        $folder = Split-Path -Path $Path -Parent
        if ($folder -and -not (Test-Path -LiteralPath $folder)) { $null = New-Item -ItemType Directory -Path $folder -Force }
        Move-Item -LiteralPath $pdf -Destination $Path -Force
    }
    finally {
        # The browser can hold its profile a moment after it exits.
        foreach ($attempt in 1..5) {
            Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
            if (-not (Test-Path -LiteralPath $work)) { break }
            Start-Sleep -Milliseconds 300
        }
    }
}
