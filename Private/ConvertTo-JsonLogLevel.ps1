function ConvertTo-JsonLogLevel {
    <#
    .SYNOPSIS
        Map the level value of a JSON log record to a canonical level.
    .DESCRIPTION
        JSON loggers disagree on how they write a level, so this accepts:

          * names understood by ConvertTo-NormalizedLevel (Serilog's
            Information/Warning/Fatal, zap's warn, ...);
          * a few JSON-only names: zap's panic/dpanic and the Google Cloud
            Logging severities alert/emergency, all folded onto ERROR;
          * pino/bunyan numeric levels (10 trace, 20 debug, 30 info, 40 warn,
            50 error, 60 fatal), as a number or a numeric string. Values are
            bucketed by range so custom pino levels land somewhere sensible.

        The extra names are kept out of Get-KnownLevelToken on purpose: that
        list also drives keyword detection inside free-text messages, where a
        word like "panic" or "alert" is far more often prose than a level.
        Returns $null for anything else.
    .PARAMETER Value
        The raw value of the level field, as produced by ConvertFrom-Json.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Position = 0)]
        [AllowNull()]
        [object] $Value
    )

    if ($null -eq $Value -or $Value -is [bool]) {
        return $null
    }

    $number = $null
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal]) {
        $number = [double] $Value
    }
    elseif ($Value -is [string] -and $Value -match '^\s*\d+(\.\d+)?\s*$') {
        $number = [double]::Parse($Value.Trim(), [System.Globalization.CultureInfo]::InvariantCulture)
    }

    if ($null -ne $number) {
        if ($number -ge 50) { return 'ERROR' }
        if ($number -ge 40) { return 'WARN' }
        if ($number -ge 30) { return 'INFO' }
        if ($number -ge 10) { return 'DEBUG' }
        return $null
    }

    if ($Value -isnot [string]) {
        return $null
    }

    $normalized = ConvertTo-NormalizedLevel -Token $Value
    if ($normalized) {
        return $normalized
    }

    switch -Regex ($Value.Trim().ToUpperInvariant()) {
        '^(PANIC|DPANIC|ALERT|EMERGENCY|EMERG)$' { return 'ERROR' }
        default                                  { return $null }
    }
}
