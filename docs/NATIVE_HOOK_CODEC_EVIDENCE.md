# Native Hook Codec Evidence Matrix

Baseline: feature/m6.13.9-unified-hook-control-v1 (2026-10-09).
Status policy: Registered != verified on a given game build. Do not infer field offset, return ABI, or working hook from a managed type name alone.

| Managed type / target | Codec key | Value / method ABI | Getter / decode | Setter / encode | Field offset | Version / binary identity | Evidence | Validation |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Percent.Scripting.Stdlib.SecureValue.SecureLong | secure-long-whole-accessor | int64, indirect base pointer; accessor signatures need per-build verification | get_Value/0 | set_Value/1 | Whole-value: 0 | Not yet bound to a tested UnityFramework UUID | Existing ZNComplexStructCodec.mm and ZNComplexStructCodecResolver.mm; existing registry and resolve expressions | Registered; game/build ABI and device behavior unverified |
| CodeStage.AntiCheat.ObscuredTypes.ObscuredInt | codestage-obscured-int | int32 with key, indirect base pointer; exact signatures version-specific | GetDecrypted/0, GetEncrypted/1 | Encrypt/2, SetEncrypted/2 | Whole-value: 0 | Not yet bound to a tested UnityFramework UUID | Existing ZNComplexStructCodec.mm and ZNComplexStructCodecResolver.mm | Registered; specific game/build behavior unverified |
| Quantum.DamageInfo | No direct whole-struct codec registered | Complex value / by-ref ARM64 mapping must be established | Unknown | Unknown | 0x48 is **historical manual UI default only**, not validated field offset | Unknown UnityFramework UUID / metadata hash | Historical UI commit 0f741d73303cb3ec55b5e85b37ed56a808620098; replaced in 039cf24f8af1785d4c3ca9dec4d51a38ba70cbb1 | Candidate only; do NOT mark supported |
| CodeStage ObscuredFloat / ObscuredLong / ObscuredDouble | Not registered | Requires verified float/SIMD or int64 ABI and version-specific key types | Official APIs/documentation are research leads, not verified runtime signatures | Same | Unknown | Unknown | CodeStage ACTk official API documentation (research candidate); no audited target metadata | Not implemented |

## Evidence required before enabling an automatic match
1. Record game version, UnityFramework UUID, IL2CPP metadata identity, architecture and target method identity.
2. Retrieve exact field metadata (name, managed type, offset, size and alignment), and independently check actual arm64 argument location (GPR vs SIMD, by-ref vs by-value).
3. Verify codec-specific getter/setter argument and return ABI; preserve encryption keys or object invariants, and validate writable bounds.
4. Save resolved field offset and codec descriptor at build preparation; client must not discover unknown codecs on menu click.
5. Test valid/invalid inputs and original restore on a controlled target; preserve debug evidence, rollback on failure.

## Auto versus manual behavior
- **Auto:** only resolves types currently registered, with validated accessor ABI; unsupported types remain unavailable.
- **Manual:** exposes historical Field Offset input (default 0x48) and SecureLong accessor configuration. This restores the old authoring UI and reuses existing StructFieldTransform validation. The default is NOT evidence that 0x48 is correct for Quantum.DamageInfo or any specific game.
- Neither branch bypasses ABI / codec / range guards in ZNNativeHookRuntime.
