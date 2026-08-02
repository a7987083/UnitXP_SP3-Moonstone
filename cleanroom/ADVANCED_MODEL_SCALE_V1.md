# Advanced Model Scale V1

This phase adds user-driven local scale controls to the advanced editor model page.

- Normal click step: 0.10
- Shift-click step: 0.01
- Reset: 1.00
- DLL-enforced range: 0.10–5.00
- Existing V2 rotation and preview tools share the same saved transform state.
- With no active preview, scale is stored for the next advanced preview.
- No team publishing, automatic relog recovery, addon messages, remote placement, or automatic clear calls are added.

The already field-tested logout-safe DLL remains the runtime baseline. This phase is distributed as an addon-only test package.
