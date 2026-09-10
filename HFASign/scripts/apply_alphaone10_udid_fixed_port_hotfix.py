#!/usr/bin/env python3
from pathlib import Path

path = Path("HFASignBuild/Ksign/Backend/Server/UDIDService.swift")
text = path.read_text()


def replace_once(old: str, new: str, label: str) -> None:
    global text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one match, found {count}")
    text = text.replace(old, new, 1)


# Keep alphaone10 retry-safe GET/ACK semantics, but restore the bridge contract
# to the fixed 127.0.0.1:14302 endpoint consumed by existing callers/dylibs.
replace_once("import Vapor\nimport Darwin\n", "import Vapor\n", "remove Darwin")
replace_once(
    "\tstatic let port = 14302\n\tstatic let bridgePorts = [14302, 49173, 50321, 51739, 53261, 54883]\n",
    "\tstatic let port = 14302\n",
    "remove bridge port pool",
)
replace_once(
    "\tprivate var backgroundTask: UIBackgroundTaskIdentifier = .invalid\n\tprivate var activePort = UDIDService.port\n",
    "\tprivate var backgroundTask: UIBackgroundTaskIdentifier = .invalid\n",
    "remove active port state",
)
replace_once(
    "\t\t\tlet selectedPort = firstAvailableBridgePort() ?? Self.port\n"
    "\t\t\tactivePort = selectedPort\n"
    "\t\t\tapp.http.server.configuration.port = selectedPort\n",
    "\t\t\tapp.http.server.configuration.port = Self.port\n",
    "restore fixed server port",
)

port_helpers = '''\n\tprivate func firstAvailableBridgePort() -> Int? {
\t\tSelf.bridgePorts.first(where: isPortAvailable)
\t}

\tprivate func isPortAvailable(_ port: Int) -> Bool {
\t\tlet descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
\t\tguard descriptor >= 0 else { return false }
\t\tdefer { Darwin.close(descriptor) }

\t\tvar address = sockaddr_in()
\t\taddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
\t\taddress.sin_family = sa_family_t(AF_INET)
\t\taddress.sin_port = in_port_t(port).bigEndian
\t\taddress.sin_addr = in_addr(s_addr: Darwin.inet_addr("127.0.0.1"))

\t\treturn withUnsafePointer(to: &address) { pointer in
\t\t\tpointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
\t\t\t\tDarwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
\t\t\t}
\t\t}
\t}
'''
replace_once(port_helpers, "", "remove dynamic port helpers")

replace_once(
    '\tprivate var profileURL: URL { URL(string: "http://127.0.0.1:\\(activePort)/profile.mobileconfig")! }\n',
    '\tprivate var profileURL: URL { URL(string: "http://127.0.0.1:\\(Self.port)/profile.mobileconfig")! }\n',
    "restore fixed profile URL",
)

replace_once(
    '\t\tguard let data = try? Data(contentsOf: url) else { return nil }\n'
    '\t\tguard name == "UDIDRequest", let text = String(data: data, encoding: .utf8) else { return data }\n'
    '\t\tlet updated = text.replacingOccurrences(\n'
    '\t\t\tof: "http://127.0.0.1:14302/udid",\n'
    '\t\t\twith: "http://127.0.0.1:\\(activePort)/udid"\n'
    '\t\t)\n'
    '\t\treturn Data(updated.utf8)\n',
    '\t\treturn try? Data(contentsOf: url)\n',
    "restore fixed Profile Service callback",
)

for forbidden in ("bridgePorts", "activePort", "firstAvailableBridgePort", "isPortAvailable", "Darwin."):
    if forbidden in text:
        raise SystemExit(f"fixed-port validation failed: leftover {forbidden}")

required = [
    'static let port = 14302',
    'app.http.server.configuration.port = Self.port',
    'http://127.0.0.1:\\(Self.port)/profile.mobileconfig',
    'app.post("bridge", "ack", ":nonce")',
    'private func bridgeResult(for nonce: String) -> BridgeResult?',
    'private func acknowledgeBridgeResult(for nonce: String) -> Bool',
]
for needle in required:
    if needle not in text:
        raise SystemExit(f"fixed-port validation failed: missing {needle}")

path.write_text(text)
print("alphaone10 UDID fixed-port hotfix applied; retry-safe GET/ACK preserved")
