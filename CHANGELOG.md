# Changelog

All notable changes to PSLogTrawler are documented here. This project adheres
to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
