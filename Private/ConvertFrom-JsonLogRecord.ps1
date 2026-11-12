function ConvertFrom-JsonLogRecord {
    <#
    .SYNOPSIS
        Parse one JSON-lines log record into timestamp, level, message and fields.
    .DESCRIPTION
        Returns a hashtable with Timestamp, Level, Message and Fields when the
        line is a single JSON object, or $null when it is not (not JSON at all,
        malformed, or a JSON array/scalar) so the caller can fall back to the
        text parser.

        For each of timestamp, level and message the first name in the
        corresponding candidate list that is present with a non-null value
        wins. Names are matched case-insensitively, so 'level' also picks up
        Serilog JsonFormatter's 'Level'. A field whose value converts cleanly
        is consumed; every other field, including a level or timestamp field
        whose value could not be understood, is kept in Fields so nothing is
        lost.

        Serilog's compact format (CLEF) omits @l for Information events, so a
        record that carries @t or @mt but no level field is treated as INFO.

        When no message field is found the whole line becomes the message,
        which keeps Select-LogError -Pattern useful on such records.
    .PARAMETER Text
        The raw log line.
    .PARAMETER TimestampField
        Candidate names for the timestamp field, in priority order.
    .PARAMETER LevelField
        Candidate names for the level field, in priority order.
    .PARAMETER MessageField
        Candidate names for the message field, in priority order.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [AllowEmptyString()]
        [string] $Text,

        [string[]] $TimestampField = @(),

        [string[]] $LevelField = @(),

        [string[]] $MessageField = @()
    )

    # Cheap pre-check: most non-JSON lines are rejected here without paying
    # for a parse attempt and the exception that comes with a failed one.
    if (-not $Text.TrimStart().StartsWith('{')) {
        return $null
    }

    try {
        # -DateKind String keeps ISO stamps as text, so they go through the
        # same parser as text logs and Fields holds the values as written.
        $record = ConvertFrom-Json -InputObject $Text -AsHashtable -DateKind String -ErrorAction Stop
    }
    catch {
        return $null
    }

    if ($record -isnot [System.Collections.IDictionary]) {
        return $null
    }

    $keys = @($record.Keys)

    # First candidate (in the caller's order) that is present and non-null.
    $find = {
        param([string[]] $Candidates)
        foreach ($candidate in $Candidates) {
            foreach ($key in $keys) {
                if ($key -eq $candidate -and $null -ne $record[$key]) {
                    return $key
                }
            }
        }
        return $null
    }

    $consumed = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)

    $timestamp = $null
    $tsKey = & $find $TimestampField
    if ($null -ne $tsKey) {
        $timestamp = ConvertTo-JsonLogTimestamp -Value $record[$tsKey]
        if ($null -ne $timestamp) { [void] $consumed.Add($tsKey) }
    }

    $level = $null
    $lvlKey = & $find $LevelField
    if ($null -ne $lvlKey) {
        $level = ConvertTo-JsonLogLevel -Value $record[$lvlKey]
        if ($level) { [void] $consumed.Add($lvlKey) }
    }
    elseif ($keys -ccontains '@t' -or $keys -ccontains '@mt') {
        $level = 'INFO'
    }

    $message = $Text.Trim()
    $msgKey = & $find $MessageField
    if ($null -ne $msgKey) {
        $value = $record[$msgKey]
        $message = if ($value -is [string]) { $value }
                   elseif ($value -is [System.Collections.IDictionary] -or $value -is [System.Collections.IList]) {
                       ConvertTo-Json -InputObject $value -Compress -Depth 20
                   }
                   else { [string] $value }
        [void] $consumed.Add($msgKey)
    }

    # [ordered] is case-insensitive, so $_.Fields.User finds "user". JSON
    # keys that differ only by case collapse onto the last one written.
    $fields = [ordered]@{}
    foreach ($key in $keys) {
        if (-not $consumed.Contains($key)) {
            $fields[$key] = $record[$key]
        }
    }

    @{
        Timestamp = $timestamp
        Level     = $level
        Message   = $message
        Fields    = $fields
    }
}
