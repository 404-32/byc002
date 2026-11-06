# Contributing

## Development

```bash
moon update
moon check --deny-warn
moon test --deny-warn
moon fmt
bash scripts/test-cli.sh
```

Before a pull request, run:

```bash
moon check --deny-warn
moon test --target wasm --deny-warn
moon test --target wasm-gc --deny-warn
moon test --target js --deny-warn
moon fmt --check
```

## Parser changes

Every parser change must include fixtures for:

1. the accepted generated syntax;
2. a malformed version of that syntax;
3. the compatibility classification;
4. the JSON/text report where behavior changes.

Unknown public syntax must fail. Do not make unsupported API disappear silently.

## Compatibility rules

Explain why a rule is source-compatible or breaking. Conservative false positives are preferable to a false compatible result, but representation-only differences such as whitespace, member order, and derive/explicit-impl placement should be normalized.

## Commit style

Use focused commits with an imperative subject, for example:

```text
Add derive/impl normalization
Fix multi-package matching
Document CLI exit codes
```

Do not commit generated build output, dependency caches, or temporary reports.
