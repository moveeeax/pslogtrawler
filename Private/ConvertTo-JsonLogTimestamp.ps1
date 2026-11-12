function ConvertTo-JsonLogTimestamp {
    <#
    .SYNOPSIS
        Turn the timestamp value of a JSON log record into a [datetime].
    .DESCRIPTION
        Accepts the shapes common JSON loggers emit:

          * ISO-8601 strings (Serilog @t, bunyan time), parsed the same way as
            text log stamps so offsets are converted to local time;
          * Unix epoch numbers (pino time in milliseconds, zap ts in seconds
            with a fraction), as a number or a numeric string.

        An epoch value carries no unit, so the unit is inferred from its
        magnitude: below 1e11 is seconds (1e11 s is the year 5138), below 1e14
        milliseconds, below 1e17 microseconds, anything larger nanoseconds.
        Epoch stamps are returned as local time, matching what
        ConvertTo-LogDateTime does for a stamp with an explicit offset.
        Returns $null when the value cannot be read as a time.
    .PARAMETER Value
        The raw value of the timestamp field, as produced by ConvertFrom-Json.
    #>
    [CmdletBinding()]
    [OutputType([Nullable[datetime]])]
    param(
        [Parameter(Position = 0)]
        [AllowNull()]
        [object] $Value
    )

    if ($null -eq $Value -or $Value -is [bool]) {
        return $null
    }

    if ($Value -is [datetime]) {
        if ($Value.Kind -eq [System.DateTimeKind]::Utc) { return $Value.ToLocalTime() }
        return $Value
    }
    if ($Value -is [System.DateTimeOffset]) {
        return $Value.LocalDateTime
    }

    $epoch = $null
    if ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal]) {
        $epoch = [double] $Value
    }
    elseif ($Value -is [string] -and $Value -match '^\s*-?\d+(\.\d+)?\s*$') {
        $epoch = [double]::Parse($Value.Trim(), [System.Globalization.CultureInfo]::InvariantCulture)
    }

    if ($null -ne $epoch) {
        $magnitude = [math]::Abs($epoch)
        # Ticks (100 ns) per unit: seconds, milliseconds, microseconds, nanoseconds.
        $ticksPerUnit = if ($magnitude -lt 1e11) { 1e7 }
                        elseif ($magnitude -lt 1e14) { 1e4 }
                        elseif ($magnitude -lt 1e17) { 10 }
                        else { 0.01 }
        try {
            return [System.DateTimeOffset]::UnixEpoch.AddTicks([long] [math]::Round($epoch * $ticksPerUnit)).LocalDateTime
        }
        catch {
            # Out of the representable DateTime range: not a usable stamp.
            return $null
        }
    }

    if ($Value -isnot [string]) {
        return $null
    }

    # Same comma-before-fraction normalization the text parser applies.
    ConvertTo-LogDateTime -Text ($Value -replace ',(\d)', '.$1')
}
