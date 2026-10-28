# Releasing

This repository uses the **Release** GitHub Actions workflow to publish a tagged release after re-running the validation suite.

## Before publishing

1. Review the unreleased changes in `CHANGELOG.md`.
2. Confirm the README configuration and examples match the current script.
3. Review the latest successful run in the **Shell checks** workflow.
4. Choose a version honestly: use `0.1.0` for an initial usable release, and do not reuse an existing tag.

## Publish a release

1. Open **Actions → Release** in the GitHub repository.
2. Select **Run workflow**, choose the `main` branch, and enter a version without the `v` prefix (for example, `0.1.0`).
3. The workflow validates the version, runs Bash syntax checks, the smoke tests, and ShellCheck, then creates the `v0.1.0` Git tag and GitHub Release.
4. The release includes `health_check.sh` and `SHA256SUMS`. Consumers can verify the downloaded script with `sha256sum -c SHA256SUMS` after placing both files in the same directory.
5. After publishing, update `CHANGELOG.md` in a follow-up commit or pull request to move the released changes into a versioned section.

The workflow can only be started from `main` and uses the repository's built-in GitHub token. Never put a personal access token in the repository or workflow file.
