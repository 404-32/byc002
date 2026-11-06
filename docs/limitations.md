# Limitations and engineering boundaries

MoonCompat is useful only within the boundary it states clearly.

## Source interface, not ABI

MoonCompat compares public `.mbti` interfaces. It does not inspect the generated binary ABI, memory layout, calling convention, or serialized format.

Two versions with identical `.mbti` can still differ behaviorally. A successful check means that supported public declarations are source-compatible under the v0.1 policy; it is not a proof of semantic equivalence.

## Conservative signature handling

Any signature difference is breaking in v0.1. This deliberately avoids unsound assumptions about optional parameters, function values, generic inference, or compiler evolution.

## Generated format coupling

The parser targets the `.mbti` format described as `mbti-v1`. Public syntax not recognized by the parser raises an error instead of being ignored. New MoonBit public declaration forms require a parser update and a new parser-version fixture.

## Visibility boundaries

Private fields omitted from `.mbti` are outside the checked surface. Representation changes that the MoonBit compiler considers non-public do not produce a report.

## Multi-package rename

Package additions and removals are compared independently. A deliberate rename of multiple packages is reported as removed and added declarations rather than inferred as a cross-package rename.

## Not implemented in v0.1

- ABI checks;
- behavioral or protocol compatibility checks;
- automatic `moon.mod` version rewriting;
- git tag fetching inside the CLI;
- SARIF output;
- a hosted web service.

These are roadmap items only when they can be backed by reproducible tests. See [ROADMAP.md](../ROADMAP.md).
