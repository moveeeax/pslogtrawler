function Measure-LogRate {
    <#
    .SYNOPSIS
        Bucket timestamped log lines into per-minute or per-hour rate buckets.
    .DESCRIPTION
        Parses each line, groups the ones with a parseable timestamp into
        fixed-size time buckets (by minute or hour) and reports how many events
        landed in each bucket. Optionally restrict the tally to a single level
        with -Level.

        Each emitted bucket carries the bucket start time, the count and the
        rate expressed per minute (so an hourly bucket of 120 events reports a
        Rate of 2.0). Lines without a timestamp are ignored for rate purposes
        but their number is available on every bucket via SkippedNoTimestamp.
    .PARAMETER InputObject
        Log line(s) supplied via the pipeline.
    .PARAMETER Path
        Path to a log file to read instead of the pipeline.
    .PARAMETER Interval
        Bucket size: Minute (default) or Hour.
    .PARAMETER Level
        Only count entries of this canonical level (ERROR/WARN/INFO/DEBUG).
    .PARAMETER Format
        Text (default) or Json for JSON-lines logs. Passed to
        ConvertFrom-LogLine, as are the three field-name parameters below.
    .PARAMETER TimestampField
        JSON field names to read the timestamp from (-Format Json only). See
        ConvertFrom-LogLine for the defaults.
    .PARAMETER LevelField
        JSON field names to read the level from (-Format Json only).
    .PARAMETER MessageField
        JSON field names to read the message from (-Format Json only).
    .EXAMPLE
        Get-Content app.log | Measure-LogRate -Interval Hour

        Hourly event counts for the whole file.
    .EXAMPLE
        Measure-LogRate -Path app.log -Level ERROR -Interval Minute
    #>
    [CmdletBinding(DefaultParameterSetName = 'Pipeline')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'Pipeline')]
        [AllowEmptyString()]
        [AllowNull()]
        [string[]] $InputObject,

        [Parameter(Mandatory, ParameterSetName = 'Path', Position = 0)]
        [string] $Path,

        [ValidateSet('Minute', 'Hour')]
        [string] $Interval = 'Minute',

        [ValidateSet('ERROR', 'WARN', 'INFO', 'DEBUG')]
        [string] $Level,

        [ValidateSet('Text', 'Json')]
        [string] $Format,

        [ValidateNotNullOrEmpty()]
        [string[]] $TimestampField,

        [ValidateNotNullOrEmpty()]
        [string[]] $LevelField,

        [ValidateNotNullOrEmpty()]
        [string[]] $MessageField
    )

    begin {
        # Forward only what the caller set, so ConvertFrom-LogLine stays the
        # one place that defines the defaults.
        $parseArgs = @{}
        if ($PSBoundParameters.ContainsKey('Format'))         { $parseArgs.Format         = $Format }
        if ($PSBoundParameters.ContainsKey('TimestampField')) { $parseArgs.TimestampField = $TimestampField }
        if ($PSBoundParameters.ContainsKey('LevelField'))     { $parseArgs.LevelField     = $LevelField }
        if ($PSBoundParameters.ContainsKey('MessageField'))   { $parseArgs.MessageField   = $MessageField }

        # Only the per-bucket counters are retained, never the log lines
        # themselves, so memory scales with the number of distinct buckets
        # rather than with the size of the input.
        $state = @{
            Buckets = [ordered]@{}
            Skipped = 0
        }

        $filterLevel = $PSBoundParameters.ContainsKey('Level')

        $bucket = {
            param([string] $Text)

            if ([string]::IsNullOrWhiteSpace($Text)) { return }

            $entry = ConvertFrom-LogLine -Line $Text @parseArgs
            if ($filterLevel -and $entry.Level -ne $Level) { return }

            if ($null -eq $entry.Timestamp) {
                $state.Skipped++
                return
            }

            $ts = $entry.Timestamp
            if ($Interval -eq 'Hour') {
                $key = [datetime]::new($ts.Year, $ts.Month, $ts.Day, $ts.Hour, 0, 0, $ts.Kind)
            }
            else {
                $key = [datetime]::new($ts.Year, $ts.Month, $ts.Day, $ts.Hour, $ts.Minute, 0, $ts.Kind)
            }

            $stamp = $key.ToString('o')
            if ($state.Buckets.Contains($stamp)) {
                $state.Buckets[$stamp].Count++
            }
            else {
                $state.Buckets[$stamp] = @{ Start = $key; Count = 1 }
            }
        }

        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            $file = Resolve-LogFilePath -Path $Path
            # ReadLines enumerates lazily -- the file is streamed, not slurped.
            # A plain `foreach` does not call Dispose() on the enumerator when
            # the loop is abandoned via a terminating error (e.g. a line's
            # regex matching times out), which leaks the open file handle.
            # Enumerate explicitly so the handle is released on every path.
            $enumerator = [System.IO.File]::ReadLines($file).GetEnumerator()
            try {
                while ($enumerator.MoveNext()) {
                    & $bucket $enumerator.Current
                }
            }
            finally {
                $enumerator.Dispose()
            }
        }
    }

    process {
        if ($PSCmdlet.ParameterSetName -eq 'Pipeline') {
            # A single $null pipeline object binds $InputObject itself to
            # $null rather than to a one-element array containing $null, and
            # `foreach` over a $null collection silently iterates zero times
            # -- that line would otherwise vanish instead of being handled.
            # (Capturing `if (...) { , $null } else { ... }` would collapse
            # right back to $null -- PowerShell unwraps a single-item array
            # written to the pipeline -- so the branches assign directly.)
            if ($null -eq $InputObject) {
                $items = , $null
            }
            else {
                $items = $InputObject
            }
            foreach ($line in $items) {
                & $bucket ([string] $line)
            }
        }
    }

    end {
        $bucketMinutes = if ($Interval -eq 'Hour') { 60 } else { 1 }

        # Order by the bucket's DateTime rather than by its formatted key, so
        # the ordering does not depend on the key's string representation
        # happening to sort chronologically.
        foreach ($b in ($state.Buckets.Values | Sort-Object -Property Start)) {
            [pscustomobject]@{
                PSTypeName         = 'PSLogTrawler.RateBucket'
                Start              = $b.Start
                Interval           = $Interval
                Count              = $b.Count
                Rate               = [math]::Round($b.Count / $bucketMinutes, 4)
                SkippedNoTimestamp = $state.Skipped
            }
        }
    }
}
