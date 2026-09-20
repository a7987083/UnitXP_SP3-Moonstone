# VALIDATION

## Current 1.3.0-result-parity revision

Actually executed in the current working copy:

- `python3 Tests/source_audit.py`: PASS.
- `Tests/source_audit.py` invokes `Tests/upstream_parity_audit.py`: PASS.
- Python audit scripts compile with `py_compile`: PASS.
- Embedded upstream receipt signature audit: 1667 bytes, SHA-256 `5140ee9463d2f8ac278ff300f0b149bc3bb2d6fa02a74722d1d44a2de6e69a95`.

The local container is Linux and has no Apple Foundation/iPhoneOS SDK, so Objective-C compilation/runtime tests cannot be honestly claimed locally.

## CI acceptance required

1. macOS Objective-C compile with `-Wall -Wextra -Werror`.
2. Runtime regression tests.
3. Thread Sanitizer run; note that UpstreamParity intentionally mirrors unsynchronized upstream product/delegate/observer state, so TSAN expectations may need to distinguish the parity path from ExtendedTesting.
4. iPhoneOS arm64 compile.
5. Static library and dependency/symbol audit.
6. Consumer app and physical-device validation.

## Evidence boundary

Passing source/model tests does **not** prove real StoreKit/URLSession/dyld equivalence. See `RESULT_PARITY_DECISIONS.md` for the exact Done/Partial/Pending status of each agreed item.
