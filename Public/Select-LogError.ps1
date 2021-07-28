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
        Regular expression the message must match.
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
        $regex = if ($PSBoundParameters.ContainsKey('Pattern')) {
            [regex]::new($Pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        }
        else { $null }

        $emit = {
            param($lines)
            foreach ($ln in $lines) {
                if ([string]::IsNullOrWhiteSpace($ln)) { continue }

                $entry = ConvertFrom-LogLine -Line $ln
                if ($entry.Level -notin $wantedLevels) { continue }

                if ($hasSince) {
                    if ($null -eq $entry.Timestamp) {
                        if ($RequireTimestamp) { continue }
                    }
                    elseif ($entry.Timestamp -lt $Since) {
                        continue
                    }
                }

                if ($regex -and -not $regex.IsMatch($entry.Message)) { continue }

                $entry
            }
        }

        if ($PSCmdlet.ParameterSetName -eq 'Path') {
            if (-not (Test-Path -LiteralPath $Path)) {
                throw "Log file not found: $Path"
            }
            & $emit (Get-Content -LiteralPath $Path)
        }
    }

    process {
        if ($PSCmdlet.ParameterSetName -eq 'Pipeline') {
            & $emit $InputObject
        }
    }
}
