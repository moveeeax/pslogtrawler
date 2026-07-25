function Select-LogError {
    <#
    .SYNOPSIS
        Filter log lines down to error/warning entries.
    .DESCRIPTION
        Parses each incoming line and emits the structured entries whose level
        is ERROR (or WARN when -IncludeWarnings is set). Results can be narrowed
        further by time (-Since) and by a regular expression matched against the
        message (-Pattern).

        Lines that have no parseable timestamp are still emitted when -Since is
        used, unless -RequireTimestamp is specified, so undated error lines are
        not silently lost.
    .PARAMETER InputObject
        Log line(s) supplied via the pipeline.
    .PARAMETER Path
        Path to a log file to read instead of the pipeline.
    .PARAMETER Since
        Only return entries at or after this timestamp.
    .PARAMETER Pattern
        Regular expression the message must match. Matched case-insensitively
        and capped at a 2 second timeout per line, so a pattern that backtracks
        catastrophically fails with a clear error instead of hanging.
    .PARAMETER IncludeWarnings
        Also return WARN entries, not just ERROR.
    .PARAMETER RequireTimestamp
        When combined with -Since, drop entries that have no parseable timestamp.
    .EXAMPLE
        Get-Content app.log | Select-LogError -Since (Get-Date).AddHours(-1)

        Errors from the last hour.
    .EXAMPLE
        Select-LogError -Path app.log -Pattern 'timeout|refused' -IncludeWarnings
    #>
    [CmdletBinding(DefaultParameterSetName = 'Pipeline')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, ParameterSetName = 'Pipeline')]
        [AllowEmptyString()]
        [string[]] $InputObject,

        [Parameter(Mandatory, ParameterSetName = 'Path', Position = 0)]
        [string] $Path,

        [datetime] $Since,

        [string] $Pattern,

        [switch] $IncludeWarnings,

        [switch] $RequireTimestamp
    )

    begin {
        $wantedLevels = if ($IncludeWarnings) { @('ERROR', 'WARN') } else { @('ERROR') }
        $hasSince = $PSBoundParameters.ContainsKey('Since')

        # Generous for any sane pattern, decisive against a pathological one.
        $matchTimeout = [timespan]::FromSeconds(2)

        $regex = $null
        if ($PSBoundParameters.ContainsKey('Pattern')) {
            try {
                # -Pattern is user supplied and is applied to untrusted log
                # text, so it is capped with a match timeout. Without one, a
                # backtracking pattern such as '(a+)+$' against an ordinary log
                # message runs effectively forever with no way to interrupt it.
                $regex = [regex]::new(
                    $Pattern,
                    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase,
                    $matchTimeout)
            }
            catch [System.ArgumentException] {
                $PSCmdlet.ThrowTerminatingError(
                    [System.Management.Automation.ErrorRecord]::new(
                        [System.ArgumentException]::new(
                            "-Pattern is not a valid regular expression: $($_.Exception.Message)", 'Pattern'),
                        'InvalidPattern',
                        [System.Management.Automation.ErrorCategory]::InvalidArgument,
                        $Pattern))
            }
        }

        $emit = {
            param([string] $Text)

            if ([string]::IsNullOrWhiteSpace($Text)) { return }

            $entry = ConvertFrom-LogLine -Line $Text
            if ($entry.Level -notin $wantedLevels) { return }

            if ($hasSince) {
                if ($null -eq $entry.Timestamp) {
                    if ($RequireTimestamp) { return }
                }
                elseif ($entry.Timestamp -lt $Since) {
                    return
                }
            }

            if ($regex) {
                try {
                    if (-not $regex.IsMatch($entry.Message)) { return }
                }
                catch [System.Text.RegularExpressions.RegexMatchTimeoutException] {
                    # Every remaining line would hit the same wall, so stop
                    # rather than quietly dropping matches.
                    $PSCmdlet.ThrowTerminatingError(
                        [System.Management.Automation.ErrorRecord]::new(
                            [System.TimeoutException]::new(
                                ("-Pattern '{0}' exceeded the {1}s match timeout. Rewrite it to avoid nested quantifiers." -f
                                    $Pattern, $matchTimeout.TotalSeconds)),
                            'PatternMatchTimeout',
                            [System.Management.Automation.ErrorCategory]::OperationTimeout,
                            $Pattern))
                }
            }

            $entry
        }

        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            $file = Resolve-LogFilePath -Path $Path
            # ReadLines enumerates lazily, so matches stream out as they are
            # found instead of the whole file being read up front.
            foreach ($line in [System.IO.File]::ReadLines($file)) {
                & $emit $line
            }
        }
    }

    process {
        if ($PSCmdlet.ParameterSetName -eq 'Pipeline') {
            foreach ($line in $InputObject) {
                & $emit ([string] $line)
            }
        }
    }
}
