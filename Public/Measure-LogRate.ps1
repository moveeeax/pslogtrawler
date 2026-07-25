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
        [string[]] $InputObject,

        [Parameter(Mandatory, ParameterSetName = 'Path', Position = 0)]
        [string] $Path,

        [ValidateSet('Minute', 'Hour')]
        [string] $Interval = 'Minute',

        [ValidateSet('ERROR', 'WARN', 'INFO', 'DEBUG')]
        [string] $Level
    )

    begin {
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

            $entry = ConvertFrom-LogLine -Line $Text
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
            foreach ($line in [System.IO.File]::ReadLines($file)) {
                & $bucket $line
            }
        }
    }

    process {
        if ($PSCmdlet.ParameterSetName -eq 'Pipeline') {
            foreach ($line in $InputObject) {
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
