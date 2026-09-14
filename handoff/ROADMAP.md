# ROADMAP

## Phase A — Runtime capture

Status: **DONE / stable baseline**

- Baseline: `feature/json-capture-v0.4.1`
- VM-ready Lua 5.3 input capture has been device-validated.
- Do not change capture hooks unless new runtime evidence requires it.

## Phase B — Lua static table recovery

Status: **DONE**

- Recharge: 947 records
- Drop: 2001 records
- Monster: 2001 records
- MonsterEX: 2001 records
- Recovery tool: `tools/lua53_static_recover.py`

## Phase C — Server authoritative comparison

Status: **IN PROGRESS / NEXT**

Goal: compare recovered client static tables against restored server JSONs and separate legitimate server/channel/operator edits from source-version differences.

Required evidence:

- `/home/ubuntu/runtime/json`
- `/home/ubuntu/runtime/wjson`
- `/home/ubuntu/runtime/www/def/Ios_json.txt`
- `/home/ubuntu/runtime/www/master/GM/tmp_process/resource_json.txt`
- `adv_gm.tt_update`
- `adv_gm.gm_resource`

Exit criteria:

- structured per-id/per-field diff for all four tables;
- classified expected vs unexpected differences;
- selected authoritative deployment files;
- hashes and rollback copy recorded.

## Phase D — Native loader extra validation

Status: **OPTIONAL / NOT BLOCKING**

When an actual Lua 5.3 runtime is available, load/list `*.normalized-format0.luac` with the native Lua 5.3 loader and record output. This is supplementary to the already completed structural/semantic recovery validation.
