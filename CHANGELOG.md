# Changelog

Notable changes to this project are documented here.

## Unreleased

### Fixed
- Escape JSON string values so host names containing quotes or backslashes cannot invalidate output.
- Validate memory values before calculating percentage usage.
- Avoid printing a healthy inode summary when an inode threshold has already triggered an alert.
- Include both IPv4 and IPv6 TCP tables in established-connection counts.
- Add a fallback for CPU core detection when `nproc` is unavailable.
- Avoid false-positive process warnings by requiring an explicit `WATCH_PROCESSES` list.

### Added
- Bash smoke tests and GitHub Actions checks for syntax, JSON output, and ShellCheck.
- Contribution and security reporting guidance.
- Issue forms for reproducible bugs and feature requests.

### Documentation
- Documented optional process monitoring and test commands.
