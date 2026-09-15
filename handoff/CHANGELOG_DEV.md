# CHANGELOG_DEV

## 2026-09-15 — Windows GUI v0.1.0

### Added

- `tools/lua53_static_recovery_gui.py`
  - native Tk/ttk Windows GUI;
  - drag/drop via `tkinterdnd2`;
  - Add File / Add Folder / Remove / Clear / Select Output / Open Output;
  - batch preflight showing size, SHA-256, format byte and instruction count;
  - threaded batch recovery with progress, records/instructions/status table and detailed log;
  - preserves original inputs and writes each input to an isolated output folder;
  - packaged `--self-test` mode for CI/runtime validation.
- `.github/workflows/build-lua53-static-recovery-windows.yml`
  - `windows-latest`, Python 3.12 x64;
  - PyInstaller 6.22.3;
  - pyinstaller-hooks-contrib 2026.7;
  - tkinterdnd2 0.6.3;
  - one-file/windowed x64 EXE build;
  - source self-test + packaged EXE self-test + release packaging.

### Validation

Local source/core smoke test against all four captured chunks:

- Recharge: 947 records / 13201 instructions / trailing=0 / unsupported=0 / format diff=[5]
- Drop: 2001 / 23925 / trailing=0 / unsupported=0 / format diff=[5]
- Monster: 2001 / 104480 / trailing=0 / unsupported=0 / format diff=[5]
- MonsterEX: 2001 / 175009 / trailing=0 / unsupported=0 / format diff=[5]

GitHub Actions Windows run `34973596147` completed successfully:

- source self-test: success
- PyInstaller single-file build: success
- packaged `Lua53StaticRecovery.exe --self-test`: success
- package/upload: success

Release artifacts:

- EXE: `Lua53StaticRecovery.exe`
  - architecture: Windows PE32+ GUI x86-64 / AMD64
  - size: 12,344,667 bytes
  - SHA-256: `d67e82b070c53e73a856111f54056839151cc85d0f19a1d9e25ef13144fcfc3d`
- ZIP: `Lua53StaticRecovery_Windows_x64_v0.1.0.zip`
  - SHA-256: `befaecb454e568d28347f7103544f6127da80c008421dba6627c00c5d693e485`
- GitHub Actions artifact digest: `sha256:a65bc53c749d2e9611385940bd5843242342db80ac6c8677d7a82a439d0c19c7`

### Limitations

- EXE is not Authenticode-signed; Windows SmartScreen may show an unknown-publisher warning.
- Current recovery engine intentionally supports the observed static Lua 5.3 table-construction opcode subset; it is not a general-purpose arbitrary Lua decompiler.

## 2026-09-15 — Lua 5.3 static recovery v0.1

### Added

- `tools/lua53_static_recover.py`
  - parses Lua 5.3 official-layout chunks;
  - accepts observed `LUAC_FORMAT=1` without mutating originals;
  - parses Proto / Code / Constants / Upvalues / child protos / debug sections;
  - executes an allow-listed static table construction opcode subset;
  - reconstructs `TAB_*[-1]` schema plus table records;
  - emits `.recovered.lua`, `.recovered.json`, `.recovered.meta.json` and format-0 copy.

### Recovered and run-validated

- `TAB_Recharge`: 947 records / 13201 instructions.
- `TAB_Drop`: 2001 records / 23925 instructions.
- `TAB_Monster`: 2001 records / 104480 instructions.
- `TAB_MonsterEX`: 2001 records / 175009 instructions.

All four:

- parsed to EOF with `trailing_bytes=0`;
- executed without unsupported opcode;
- normalized copy differs from original only at byte offset `0x05` (`1 -> 0`);
- original and normalized reconstruction produce identical canonical semantic hashes.

### Historical regression check

`Recharge.test_channel_21825.json`:

- 295/307 rows exact-match recovered content when ignoring id;
- 307/307 match business fields when ignoring id/channel/des;
- 12 remaining exact mismatches correspond to historical `TEST-Pandora-21825` test-channel entries.

### Not run

- No native `lua5.3/luac5.3` loader execution in current container: executable unavailable and outbound DNS unavailable.
- No server deployment performed.
- No new dylib build or device test was required in this phase; runtime capture baseline remains v0.4.1.
