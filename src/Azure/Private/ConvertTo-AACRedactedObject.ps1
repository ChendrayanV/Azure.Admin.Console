function ConvertTo-AACRedactedObject {
    <#
    .SYNOPSIS
        Copies an object (hashtables, lists and values, as JSON is parsed)
        with its secrets replaced by '[REDACTED]' - for anything written to
        a file that may be sent to someone else.
    .DESCRIPTION
        A value is redacted when its key names a secret (password, secret,
        token, connection string, SAS, credentials, access/account/shared
        access/primary/secondary/instrumentation key, private key) or when
        the value itself looks like one (a connection string with
        AccountKey=, SharedAccessKey=, Password= or SharedAccessSignature=,
        a SAS query string with sig=, a JWT, a PEM private key).

        Names that only mention a key (keyVaultUri, keySource, publicKey,
        keyName) are kept: they say where a secret lives, not what it is.
        -Count is a [ref] to an int that is increased once per redaction.
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        $InputObject,

        [ref] $Count
    )

    $secretKey = '(?i)(^|[_\-.])?(password|passwd|pwd|secret|clientsecret|token|accesstoken|refreshtoken|connectionstring|connectionstrings|sas|sastoken|sasurl|saskey|credential|credentials|privatekey|accesskey|accountkey|sharedaccesskey|primarykey|secondarykey|primarymasterkey|secondarymasterkey|primaryreadonlymasterkey|secondaryreadonlymasterkey|instrumentationkey|adminpassword|storageaccountkey|apikey|subscriptionkey)$'
    $secretValue = '(?i)(AccountKey=|SharedAccessKey=|SharedAccessSignature=|Password=|Pwd=)[^;]+|[?&]sig=[^&\s]+|^eyJ[\w-]+\.[\w-]+\.[\w-]+$|-----BEGIN [A-Z ]*PRIVATE KEY-----'
    $walk = {
        param($Value, [string] $Name)
        if ($null -eq $Value) { return $null }
        if ($Value -is [System.Collections.IDictionary]) {
            $copy = [ordered]@{}
            foreach ($k in $Value.Keys) { $copy[[string]$k] = & $walk $Value[$k] ([string]$k) }
            return $copy
        }
        if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
            return , @(foreach ($item in $Value) { & $walk $item $Name })
        }
        if ($Value -is [string] -and $Value) {
            if (($Name -and $Name -match $secretKey) -or $Value -match $secretValue) {
                if ($Count) { $Count.Value++ }
                return '[REDACTED]'
            }
        }
        $Value
    }
    & $walk $InputObject ''
}
