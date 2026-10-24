function Save-AACDevOpsYaml {
    <#
    .SYNOPSIS
        Writes every pipeline Read-AACDevOpsInventory read to a folder, for
        offline review and diffs: YAML pipelines and the templates they
        include as .yml, classic pipelines' steps as .classic.json.
    .DESCRIPTION
        Layout, under -Path:
          <organization>/<project>/<pipeline> (#id).yml
          <organization>/<project>/<pipeline> (#id).classic.json
          <organization>/templates/<project>/<repository>/<path>
        Names that aren't valid in a file name have those characters
        replaced with '_'. Files are written as UTF-8 without a BOM, with the
        content as Azure DevOps holds it, so two runs diff cleanly.

        A classic pipeline's file holds its name, folder, repository,
        variable groups (by name) and process (phases, steps, inputs) - not
        its variables: a secret variable's value is never returned by Azure
        DevOps, and the others are left out with it.

        Returns how many files were written.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [hashtable] $Read,

        [Parameter(Mandatory)]
        [string] $Path
    )

    $safe = { param([string] $Text) $clean = ($Text -replace '[\\/:*?"<>|\x00-\x1f]', '_').Trim().TrimEnd('.'); if ($clean) { $clean } else { '_' } }
    $utf8 = [System.Text.UTF8Encoding]::new($false)
    $written = 0
    $write = {
        param([string[]] $Parts, [string] $Content)
        $target = $Path
        foreach ($part in $Parts) { $target = Join-Path -Path $target -ChildPath $part }
        $folder = Split-Path -Path $target -Parent
        if (-not (Test-Path -LiteralPath $folder)) { $null = New-Item -Path $folder -ItemType Directory -Force }
        [System.IO.File]::WriteAllText($target, $Content, $utf8)
    }
    $orgFolder = & $safe ([string]$Read.OrganizationName)
    $projectName = @{}
    foreach ($p in @($Read.Projects)) { if ($p) { $projectName[[string]$p['id']] = [string]$p['name'] } }
    # A local template is keyed by its repository's ID: the folder takes the repository's name.
    $repositoryName = @{}
    foreach ($answer in @($Read.Repositories.Values)) { if ($answer -and -not $answer['Error']) { foreach ($r in @($answer['Items'] | Where-Object { $_ })) { $repositoryName[[string]$r['id']] = [string]$r['name'] } } }

    foreach ($projectId in @($Read.Definitions.Keys)) {
        $answer = $Read.Definitions[$projectId]
        if (-not $answer -or $answer['Error']) { continue }
        $projectFolder = & $safe $(if ($projectName.ContainsKey($projectId)) { $projectName[$projectId] } else { $projectId })
        foreach ($d in @($answer['Items'] | Where-Object { $_ })) {
            $fileName = & $safe "$([string]$d['name']) (#$($d['id']))"
            if ([int](Get-AACMember -InputObject $d -Path 'process.type') -eq 2) {
                $entry = $Read.Yaml["$projectId|$($d['id'])"]
                if ($entry -and $entry.Content) { & $write @($orgFolder, $projectFolder, "$fileName.yml") $entry.Content; $written++ }
            }
            else {
                $classic = [ordered]@{
                    name           = [string]$d['name']
                    id             = $d['id']
                    path           = [string]$d['path']
                    repository     = [string](Get-AACMember -InputObject $d -Path 'repository.name')
                    variableGroups = @(@(Get-AACMember -InputObject $d -Path 'variableGroups') | Where-Object { $_ } | ForEach-Object { [string]$_['name'] })
                    process        = Get-AACMember -InputObject $d -Path 'process'
                }
                & $write @($orgFolder, $projectFolder, "$fileName.classic.json") (ConvertTo-Json -InputObject $classic -Depth 30)
                $written++
            }
        }
    }
    foreach ($key in @($Read.TemplateContent.Keys)) {
        $tc = $Read.TemplateContent[$key]
        if (-not $tc.Content) { continue }
        $project, $repository, $null, $file = $key -split '\|', 4
        $projectLabel = if ($projectName.ContainsKey($project)) { $projectName[$project] } else { $project }
        $parts = @($orgFolder, 'templates', (& $safe $projectLabel), (& $safe $(if ($repositoryName.ContainsKey($repository)) { $repositoryName[$repository] } else { $repository }))) + @($file -split '/' | Where-Object { $_ -and $_ -ne '..' } | ForEach-Object { & $safe $_ })
        & $write $parts $tc.Content
        $written++
    }
    $written
}
