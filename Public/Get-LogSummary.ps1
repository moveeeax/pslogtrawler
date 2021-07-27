function Get-LogSummary {
    <#
    .SYNOPSIS
        Tally log lines by level and return a summary object.
    .DESCRIPTION
        Reads log content from a file (-Path) or from the pipeline (-InputObject)
        and counts how many lines fall into each canonical level
        (ERROR/WARN/INFO/DEBUG). Lines with no recognizable level are counted
        under Unknown. Blank lines are skipped by default.

        The returned object also carries the time span covered by the lines
        that had a parseable timestamp (First/Last), which makes it handy for a
        quick "what happened in this file" glance.
    .PARAMETER Path
        Path to a log file to read.
    .PARAMETER InputObject
        Log line(s) supplied via the pipeline.
    .PARAMETER IncludeBlank
        Count blank/whitespace-only lines instead of skipping them.
    .EXAMPLE
        Get-LogSummary -Path ./app.log

        Returns counts by level plus Total and the covered time range.
    .EXAMPLE
        Get-Content app.log | Get-LogSummary
    #>
    [CmdletBinding(DefaultParameterSetName = 'Pipeline')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Path', Position = 0)]
        [string] $Path,

        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'Pipeline')]
        [AllowEmptyString()]
        [string[]] $InputObject,

        [switch] $IncludeBlank
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
        $counts = [ordered]@{ ERROR = 0; WARN = 0; INFO = 0; DEBUG = 0; Unknown = 0 }
        $total = 0
        $blank = 0
        $first = $null
        $last  = $null

        foreach ($ln in $collected) {
            if ([string]::IsNullOrWhiteSpace($ln) -and -not $IncludeBlank) {
                $blank++
                continue
            }

            $total++
            $entry = ConvertFrom-LogLine -Line $ln

            if ($entry.Level) {
                $counts[$entry.Level]++
            }
            else {
                $counts['Unknown']++
            }

            if ($entry.Timestamp) {
                if ($null -eq $first -or $entry.Timestamp -lt $first) { $first = $entry.Timestamp }
                if ($null -eq $last  -or $entry.Timestamp -gt $last)  { $last  = $entry.Timestamp }
            }
        }

        [pscustomobject]@{
            PSTypeName   = 'PSLogTrawler.LogSummary'
            Total        = $total
            Error        = $counts['ERROR']
            Warn         = $counts['WARN']
            Info         = $counts['INFO']
            Debug        = $counts['DEBUG']
            Unknown      = $counts['Unknown']
            BlankSkipped = $blank
            First        = $first
            Last         = $last
        }
    }
}
