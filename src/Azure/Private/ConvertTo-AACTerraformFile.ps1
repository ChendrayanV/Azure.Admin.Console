function ConvertTo-AACTerraformFile {
    <#
    .SYNOPSIS
        Lays out what the Azure Export for Terraform API returned - one
        export, or several (batches, and the azapi pass) - as one Terraform
        folder you can run: the files and their text, and every exported
        resource with its Terraform address and Azure ID.
    .DESCRIPTION
        -Source takes each export's result, in order: @{ Result (its
        configuration and import); Provider (azurerm or azapi); File
        (main.tf or azapi.tf) }. Each configuration carries its own
        terraform and provider blocks; a module may declare its providers
        only once, so they are merged:
          terraform.tf   one terraform block, required_providers of all
          providers.tf   the provider blocks - subscription_id added where
                         missing, so the folder runs without
                         ARM_SUBSCRIPTION_ID (azurerm 4 requires one)
          main.tf        the azurerm resources
          azapi.tf       the azapi resources
          import.tf      the import blocks of all
        A resource two exports both returned (a child exported with its
        parent's batch and again on its own) is kept once - the first - and
        references to the other copy are pointed at it.

        -Primary and -Fallback are the two-export shorthand: the first
        export, and the azapi export of what it skipped.

        Returns @{ Files (ordered: name -> text); Imports (@{ Address; Id;
        Provider; File }); Duplicates (how many were dropped) }.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Source')]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Source')]
        [AllowEmptyCollection()]
        [object[]] $Source,

        [Parameter(Mandatory, ParameterSetName = 'Pair')]
        [System.Collections.IDictionary] $Primary,

        [Parameter(ParameterSetName = 'Pair')]
        [System.Collections.IDictionary] $Fallback,

        [Parameter(Mandatory, ParameterSetName = 'Pair')]
        [string] $PrimaryProvider,

        [string] $SubscriptionId
    )

    if ($PSCmdlet.ParameterSetName -eq 'Pair') {
        $Source = @(@{ Result = $Primary; Provider = $PrimaryProvider; File = $(if ($PrimaryProvider -eq 'azapi') { 'azapi.tf' } else { 'main.tf' }) })
        if ($Fallback) { $Source += @{ Result = $Fallback; Provider = 'azapi'; File = 'azapi.tf' } }
    }

    $requiredProviders = [ordered]@{}
    $providers = [ordered]@{}
    $imports = [System.Collections.Generic.List[hashtable]]::new()
    $files = [ordered]@{}
    $resourceText = [ordered]@{ 'main.tf' = [System.Collections.Generic.List[hashtable]]::new(); 'azapi.tf' = [System.Collections.Generic.List[hashtable]]::new() }
    $importText = [System.Collections.Generic.List[string]]::new()
    $kept = @{}
    $renamed = @{}
    $duplicates = 0

    # The text between the braces of the first "<name> {" in a block, or ''.
    $body = {
        param([string] $Block, [string] $Name)
        $open = [regex]::Match($Block, "(?m)\b$([regex]::Escape($Name))\s*\{")
        if (-not $open.Success) { return '' }
        $parts = @(Split-AACHclBlock -Text "x $($Block.Substring($open.Index + $open.Length - 1))")
        if (-not $parts.Count) { return '' }
        $t = [string]$parts[0].Text
        $t.Substring($t.IndexOf('{') + 1, $t.LastIndexOf('}') - $t.IndexOf('{') - 1)
    }

    foreach ($item in $Source) {
        $result = if ($item.Result -is [System.Collections.IDictionary]) { $item.Result } else { @{} }
        $file = [string]$item.File
        if (-not $resourceText.Contains($file)) { $resourceText[$file] = [System.Collections.Generic.List[hashtable]]::new() }

        # Its imports first: an Azure ID already exported means this copy of the resource goes.
        $dropped = @{}
        foreach ($block in @(Split-AACHclBlock -Text ([string]$result['import']) | Where-Object { $_.Type -eq 'import' })) {
            $id = [regex]::Match($block.Text, '\bid\s*=\s*"([^"]+)"')
            $to = [regex]::Match($block.Text, '\bto\s*=\s*([^\s}]+)')
            if (-not ($id.Success -and $to.Success)) { continue }
            $address = $to.Groups[1].Value
            $same = ($id.Groups[1].Value -split '\?')[0].ToLowerInvariant()
            if ($kept.ContainsKey($same)) { $duplicates++; if ($address -ne $kept[$same]) { $renamed[$address] = $kept[$same] }; $dropped[$address] = $true; continue }
            $kept[$same] = $address
            $imports.Add(@{ Address = $address; Id = $id.Groups[1].Value; Provider = [string]$item.Provider; File = $file })
            $importText.Add([string]$block.Text)
        }

        foreach ($block in @(Split-AACHclBlock -Text ([string]$result['configuration']))) {
            switch ($block.Type) {
                'terraform' {
                    # Each entry of required_providers: "azurerm = { source = ..., version = ... }".
                    $inner = & $body $block.Text 'required_providers'
                    foreach ($entry in [regex]::Matches($inner, '(?m)^\s*([A-Za-z_][A-Za-z0-9_-]*)\s*=\s*\{')) {
                        $name = $entry.Groups[1].Value
                        if ($requiredProviders.Contains($name)) { continue }
                        # Its attributes, one per line - laid out again with the same indentation whatever the source used.
                        $value = @(Split-AACHclBlock -Text "x $($inner.Substring($entry.Index + $entry.Length - 1))")
                        if ($value.Count) {
                            $t = [string]$value[0].Text
                            $requiredProviders[$name] = @($t.Substring($t.IndexOf('{') + 1, $t.LastIndexOf('}') - $t.IndexOf('{') - 1) -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
                        }
                    }
                }
                'provider' {
                    $name = if ($block.Labels.Count) { [string]$block.Labels[0] } else { '' }
                    if ($name -and -not $providers.Contains($name)) {
                        $text = [string]$block.Text
                        if ($SubscriptionId -and $name -in 'azurerm', 'azapi' -and $text -notmatch '\bsubscription_id\s*=') {
                            $brace = $text.IndexOf('{')
                            $text = $text.Substring(0, $brace + 1) + "`n  subscription_id = `"$SubscriptionId`"" + $text.Substring($brace + 1)
                        }
                        $providers[$name] = $text
                    }
                }
                default {
                    $address = if ($block.Type -eq 'resource' -and $block.Labels.Count -ge 2) { "$($block.Labels[0]).$($block.Labels[1])" } else { '' }
                    if ($address -and $dropped.ContainsKey($address)) { continue }
                    $resourceText[$file].Add(@{ Text = [string]$block.Text })
                }
            }
        }
    }

    # References to a dropped copy point at the one kept.
    $repoint = {
        param([string] $Text)
        foreach ($from in $renamed.Keys) { $Text = [regex]::Replace($Text, "(?<![\w.-])$([regex]::Escape($from))(?![\w-])", [string]$renamed[$from]) }
        $Text
    }

    $nl = "`n"
    if ($requiredProviders.Count) {
        $entries = foreach ($name in $requiredProviders.Keys) { "    $name = {$nl$(@($requiredProviders[$name] | ForEach-Object { "      $_" }) -join $nl)$nl    }" }
        $files['terraform.tf'] = "terraform {$nl  required_providers {$nl$($entries -join $nl)$nl  }$nl}$nl"
    }
    if ($providers.Count) { $files['providers.tf'] = (@($providers.Values) -join "$nl$nl") + $nl }
    foreach ($file in $resourceText.Keys) {
        if ($resourceText[$file].Count) { $files[$file] = (@($resourceText[$file] | ForEach-Object { & $repoint $_.Text }) -join "$nl$nl") + $nl }
    }
    if ($importText.Count) { $files['import.tf'] = (@($importText) -join "$nl$nl") + $nl }

    @{ Files = $files; Imports = $imports.ToArray(); Duplicates = $duplicates }
}
