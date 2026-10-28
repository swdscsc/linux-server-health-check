# Contributing

Thanks for considering a contribution.

## Before opening a pull request

1. Open an issue first for substantial changes so the scope can be discussed.
2. Keep changes focused and explain the user-visible problem they solve.
3. Do not include credentials, tokens, production logs with sensitive data, or private host information.
4. Run the checks below before submitting.

\`\`\`bash
bash -n src/health_check.sh tests/test_health_check.sh
bash tests/test_health_check.sh
shellcheck --severity=warning src/health_check.sh tests/test_health_check.sh
\`\`\`

## Pull request description

Please include the motivation, a summary of behavior changes, test evidence, and any known limitations. Configuration defaults should remain conservative and be documented in the README.
