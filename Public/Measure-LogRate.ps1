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
        $collected = [System.Collections.Generic.List[string]]::new()

        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (-not (Test-Path -LiteralPath $Path)) {
                throw "Log file not found: $Path"
            }
            foreach ($ln in (Get-Content -LiteralPath $Path)) {
                $collected.Add([string] $ln)
            }
        }
    }

    process {
        if ($PSCmdlet.ParameterSetName -eq 'Pipeline') {
            foreach ($ln in $InputObject) {
                $collected.Add([string] $ln)
            }
        }
    }

    end {
        $filterLevel = $PSBoundParameters.ContainsKey('Level')
        $bucketMinutes = if ($Interval -eq 'Hour') { 60 } else { 1 }

        $buckets = [ordered]@{}
        $skipped = 0

        foreach ($ln in $collected) {
            if ([string]::IsNullOrWhiteSpace($ln)) { continue }

            $entry = ConvertFrom-LogLine -Line $ln
            if ($filterLevel -and $entry.Level -ne $Level) { continue }

            if ($null -eq $entry.Timestamp) {
                $skipped++
                continue
            }

            $ts = $entry.Timestamp
            if ($Interval -eq 'Hour') {
                $key = [datetime]::new($ts.Year, $ts.Month, $ts.Day, $ts.Hour, 0, 0, $ts.Kind)
            }
            else {
                $key = [datetime]::new($ts.Year, $ts.Month, $ts.Day, $ts.Hour, $ts.Minute, 0, $ts.Kind)
            }

            $stamp = $key.ToString('o')
            if ($buckets.Contains($stamp)) {
                $buckets[$stamp] = @{ Start = $key; Count = $buckets[$stamp].Count + 1 }
            }
            else {
                $buckets[$stamp] = @{ Start = $key; Count = 1 }
            }
        }

        foreach ($stamp in ($buckets.Keys | Sort-Object)) {
            $b = $buckets[$stamp]
            [pscustomobject]@{
                PSTypeName         = 'PSLogTrawler.RateBucket'
                Start              = $b.Start
                Interval           = $Interval
                Count              = $b.Count
                Rate               = [math]::Round($b.Count / $bucketMinutes, 4)
                SkippedNoTimestamp = $skipped
            }
        }
    }
}
