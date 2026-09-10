# zonoe / HFASign Build

## Baseline
- Branch: `work/hfapatchipa-ksign-v3`
- Stable source commit: `1bfa241813e71aecebf5b7607a23c3c3f486e172`
- Version: `v3.0.0-alphaone10`

## CI
Workflow: `.github/workflows/hfasign-build.yml`

The workflow reconstructs from pinned upstream source, applies the canonical patch stack, applies the alphaone10 reliability transform, then applies the fixed-port UDID hotfix before building.

## Reconstruction
```bash
bash HFASign/scripts/reconstruct_alphaone10.sh
```

Pinned upstream:
```text
Nyasami/Ksign
03a3a9c86897d79f9faf8106037b9971841d56a0
```

## Build Result
Reference successful run:
```text
Run #124
Run ID: 34473371221
Result: success
```

Artifact:
```text
zonoe_v3.0.0-alphaone10_TrollStore.ipa
SHA256: 09a6def300ddc3a9a332df31b41d60b8bb3d206f2522a8b63ee90f421ee7b403
```

## Validation Boundary
CI success confirms reconstruction, compiler/build, packaging and repository regression checks. Current app behavior has additionally been confirmed usable by the user and is the stable functional baseline.
