function Resolve-LogFilePath {
    <#
    .SYNOPSIS
        Validate a -Path argument and return the concrete filesystem path.
    .DESCRIPTION
        Confirms the path exists and is a file (not a directory), then resolves
        it to a real provider path so callers can hand it straight to
        [System.IO.File]::ReadLines and stream the file a line at a time.

        Streaming matters here: the cmdlets in this module are aimed at log
        files, which routinely run to gigabytes. Materializing one into an
        in-memory array costs roughly 35x the file size in managed heap, so the
        aggregating cmdlets read lazily instead.
    .PARAMETER Path
        Path to the log file. May be relative or provider-qualified.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Log file not found: $Path"
    }
    if (Test-Path -LiteralPath $Path -PathType Container) {
        throw "Expected a log file but found a directory: $Path"
    }

    $resolved = Resolve-Path -LiteralPath $Path
    if ($resolved.Provider.Name -ne 'FileSystem') {
        throw "Only filesystem paths can be read as logs, but '$Path' resolved to the $($resolved.Provider.Name) provider."
    }

    $resolved.ProviderPath
}
