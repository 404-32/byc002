## Summary

Describe the user-visible change.

## Compatibility rules

- [ ] Added or updated parser fixtures.
- [ ] Added or updated compatibility tests.
- [ ] Unknown public syntax still fails closed.
- [ ] JSON output remains deterministic.

## Verification

- [ ] `moon check --deny-warn`
- [ ] `moon test --deny-warn`
- [ ] `moon fmt --check`
- [ ] `bash scripts/test-cli.sh`
