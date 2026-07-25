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

        The tally is a running aggregate, so the log is never held in memory:
        both -Path and pipeline input are consumed a line at a time and memory
        stays flat no matter how large the log is.
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
        # All mutable state lives in one object so the shared per-line routine
        # below can update it from its own scope.
        $state = @{
            Counts       = [ordered]@{ ERROR = 0; WARN = 0; INFO = 0; DEBUG = 0; Unknown = 0 }
            Total        = 0
            Blank        = 0
            First        = $null
            Last         = $null
            IncludeBlank = [bool] $IncludeBlank
        }

        $tally = {
            param([string] $Text)

            if ([string]::IsNullOrWhiteSpace($Text) -and -not $state.IncludeBlank) {
                $state.Blank++
                return
            }

            $state.Total++
            $entry = ConvertFrom-LogLine -Line $Text

            if ($entry.Level) { $state.Counts[$entry.Level]++ }
            else              { $state.Counts['Unknown']++ }

            if ($entry.Timestamp) {
                if ($null -eq $state.First -or $entry.Timestamp -lt $state.First) { $state.First = $entry.Timestamp }
                if ($null -eq $state.Last  -or $entry.Timestamp -gt $state.Last)  { $state.Last  = $entry.Timestamp }
            }
        }

        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            $file = Resolve-LogFilePath -Path $Path
            # ReadLines enumerates lazily -- the file is streamed, not slurped.
            foreach ($line in [System.IO.File]::ReadLines($file)) {
                & $tally $line
            }
        }
    }

    process {
        if ($PSCmdlet.ParameterSetName -eq 'Pipeline') {
            foreach ($line in $InputObject) {
                & $tally ([string] $line)
            }
        }
    }

    end {
        [pscustomobject]@{
            PSTypeName   = 'PSLogTrawler.LogSummary'
            Total        = $state.Total
            Error        = $state.Counts['ERROR']
            Warn         = $state.Counts['WARN']
            Info         = $state.Counts['INFO']
            Debug        = $state.Counts['DEBUG']
            Unknown      = $state.Counts['Unknown']
            BlankSkipped = $state.Blank
            First        = $state.First
            Last         = $state.Last
        }
    }
}
