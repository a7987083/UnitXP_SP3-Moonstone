# Login10195Diag v0.5

Purpose: trace the successful 10195 trigger path identified from v0.4 without modifying game state.

Instrumented UnityFramework RVAs:
- 0x1137C04
- 0x1137EA4
- 0x1138FB0
- 0x1148A58
- 0x1148C80

Each hit logs x0-x7, LR/LR RVA, SP/FP, timestamp and thread id. `send` is also hooked only to mark outbound 10003/10195 timing.

Log path:
`Documents/Login10195Diag_v0.5.log`

Recommended A/B test:
1. Launch once on domestic direct network until the zone-list failure is reproduced.
2. Relaunch with the proxy/network environment where zones succeed.
3. Compare the first probe present only in the successful path, then disassemble that caller/branch next.
