# Changelog

All notable changes to PSLogTrawler are documented here. This project adheres
to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- A parse failure in any `Public/*.ps1` no longer leaves the module importable
  with that command silently missing. The loader now fails the import, and it
  verifies that every function named in the manifest's `FunctionsToExport` was
  actually defined.
- `Get-LogSummary`, `Select-LogError` and `Measure-LogRate` stream their input
  instead of reading the whole log into memory first. Summarizing a 25 MB log
  previously threw `OutOfMemoryException` under a 96 MB heap cap; it now
  completes, and got about 4x faster as a side effect.
- `Select-LogError -Pattern` applies a two-second match timeout, so a
  catastrophically backtracking pattern fails with a clear error instead of
  running unbounded. An invalid pattern is now reported as an argument error
  rather than a raw `MethodInvocationException`.
- `-Path` arguments that name a directory are rejected with a clear message.
- `Get-LogSummary`, `Select-LogError` and `Measure-LogRate` no longer leak the
  open file handle from `-Path` when a line handler throws mid-stream (most
  reachable via `Select-LogError -Pattern`'s own match-timeout error). The
  leaked handle previously blocked deleting or rotating the log file right
  after catching the error.
- A `$null` item in pipeline input is now treated the same as an empty line
  instead of raising a per-item binding error (or, once bindable, silently
  vanishing without even being counted as blank).

### Changed

- `ConvertFrom-LogLine` compiles its regexes once per session rather than on
  every call, roughly halving per-line parse cost.

### Added

- GitHub Actions CI running manifest validation, PSScriptAnalyzer and Pester on
  Linux, Windows and macOS.

## [0.1.0] - 2021-09-05

### Added

- `ConvertFrom-LogLine` — parse a log line into `Timestamp` / `Level` /
  `Message`, supporting ISO-8601 bracketed and syslog-ish formats.
- `Get-LogSummary` — tally lines by level with the covered time range.
- `Select-LogError` — filter to errors/warnings by `-Since` and `-Pattern`.
- `Measure-LogRate` — bucket timestamped events per minute or hour.
- Table formatting views for summary and rate objects.
- Pester 5.x test suite and a sample log fixture.

### Fixed

- Comma-style fractional seconds (log4j/log4net) no longer leak into the
  parsed message.
