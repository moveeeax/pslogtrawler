function ConvertTo-LogDateTime {
    <#
    .SYNOPSIS
        Best-effort parse of a timestamp string found in a log line.
    .DESCRIPTION
        Handles ISO-8601 style stamps (2021-08-14T13:45:22, optional
        fractional seconds and offset) and classic syslog stamps that omit the
        year (e.g. "Aug 14 13:45:22"). Syslog stamps are assigned a year via
        the -DefaultYear parameter (current year by default). Returns $null
        when nothing parses so callers can skip malformed lines.
    #>
    [CmdletBinding()]
    [OutputType([Nullable[datetime]])]
    param(
        [Parameter(Position = 0)]
        [string] $Text,

        [int] $DefaultYear = (Get-Date).Year
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $null
    }

    $trimmed = $Text.Trim()

    # ISO-8601-ish: let .NET handle offsets and fractional seconds.
    [datetime] $parsed = [datetime]::MinValue
    $styles = [System.Globalization.DateTimeStyles]::AssumeLocal
    if ([datetime]::TryParse($trimmed, [System.Globalization.CultureInfo]::InvariantCulture, $styles, [ref] $parsed)) {
        return $parsed
    }

    # Syslog style without a year, e.g. "Aug 14 13:45:22".
    $withYear = '{0} {1}' -f $trimmed, $DefaultYear
    $syslogFormats = @(
        'MMM d HH:mm:ss yyyy',
        'MMM  d HH:mm:ss yyyy',
        'MMM dd HH:mm:ss yyyy'
    )
    foreach ($fmt in $syslogFormats) {
        if ([datetime]::TryParseExact($withYear, $fmt,
                [System.Globalization.CultureInfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::AssumeLocal, [ref] $parsed)) {
            return $parsed
        }
    }

    return $null
}
