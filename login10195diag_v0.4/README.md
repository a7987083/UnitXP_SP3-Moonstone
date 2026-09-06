# Login10195Diag v0.4

Authorized runtime diagnostic build for the project's own client/server login flow.

v0.4 keeps the v0.3 outbound and QuickSDK diagnostics and adds inbound socket tracing:

- TX: send / sendto / sendmsg / write / writev
- RX: recv / recvfrom / recvmsg / read / readv
- Watches 10003 (0x2713) and 10195 (0x27D3)
- Targets likely responses 20003 (0x4E23) and 20195 (0x4EE3)
- After TX 10003, logs all inbound Agent :7000/:7001 payloads for 5 seconds even when the response opcode is unknown
- Logs peer, frame header, hex preview, caller and targeted backtrace

Log file:
`Documents/Login10195Diag_v0.4.log`

Recommended A/B test: one domestic direct launch that fails to show zones, then one proxy/Japan launch that succeeds. Compare the RX blocks immediately after TX 10003.
