## Summary
<!-- What changed and why? -->

## Validation
- [ ] `bash -n src/health_check.sh tests/test_health_check.sh`
- [ ] `bash tests/test_health_check.sh`
- [ ] `shellcheck --severity=warning src/health_check.sh tests/test_health_check.sh`

## Maintainer checklist
- [ ] Defaults are documented.
- [ ] No tokens, secrets, or private production data are included.
- [ ] Behavior changes and known limitations are described.
