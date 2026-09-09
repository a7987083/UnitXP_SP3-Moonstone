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

replace_once(
    "import Vapor\n",
    "import Vapor\nimport Darwin\n",
    "import Darwin",
)

replace_once(
    "\tstatic let port = 14302\n",
    "\tstatic let port = 14302\n\tstatic let bridgePorts = [14302, 49173, 50321, 51739, 53261, 54883]\n",
    "bridge port pool",
)

replace_once(
    "\tprivate var backgroundTask: UIBackgroundTaskIdentifier = .invalid\n",
    "\tprivate var backgroundTask: UIBackgroundTaskIdentifier = .invalid\n\tprivate var activePort = Self.port\n",
    "active port state",
)

replace_once(
    "\t\t\tapp.http.server.configuration.port = Self.port\n",
    "\t\t\tlet selectedPort = firstAvailableBridgePort() ?? Self.port\n"
    "\t\t\tactivePort = selectedPort\n"
    "\t\t\tapp.http.server.configuration.port = selectedPort\n",
    "server port selection",
)

replace_once(
    "\t\t\t\t\t  let result = self.consumeBridgeResult(for: nonce) else {\n",
    "\t\t\t\t\t  let result = self.bridgeResult(for: nonce) else {\n",
    "retry-safe result lookup",
)

replace_once(
    "\n\t\t\t\tself.endBackgroundTask()\n\t\t\t\treturn Response(\n",
    "\n\t\t\t\treturn Response(\n",
    "do not end background task on GET",
)

ack_route = '''\t\t\tapp.post("bridge", "ack", ":nonce") { req -> Response in
\t\t\t\tguard let nonce = req.parameters.get("nonce"), self.isValidBridgeNonce(nonce) else {
\t\t\t\t\treturn Response(status: .badRequest, headers: ["Connection": "close"])
\t\t\t\t}
\t\t\t\tlet acknowledged = self.acknowledgeBridgeResult(for: nonce)
\t\t\t\tif acknowledged { self.endBackgroundTaskIfIdle() }
\t\t\t\treturn Response(status: acknowledged ? .noContent : .notFound, headers: ["Connection": "close"])
\t\t\t}
'''
replace_once(
    '\t\t\tapp.post("udid") { req -> Response in\n',
    ack_route + '\t\t\tapp.post("udid") { req -> Response in\n',
    "ACK route",
)

old_store = '''\tprivate func consumeBridgeResult(for nonce: String) -> BridgeResult? {
\t\tguard isValidBridgeNonce(nonce) else { return nil }
\t\tbridgeLock.lock()
\t\tdefer { bridgeLock.unlock() }

\t\tguard let result = bridgeResults.removeValue(forKey: nonce), result.expiresAt > Date() else {
\t\t\treturn nil
\t\t}
\t\treturn result
\t}
'''
new_store = '''\tprivate func bridgeResult(for nonce: String) -> BridgeResult? {
\t\tguard isValidBridgeNonce(nonce) else { return nil }
\t\tbridgeLock.lock()
\t\tdefer { bridgeLock.unlock() }

\t\tguard let result = bridgeResults[nonce] else { return nil }
\t\tguard result.expiresAt > Date() else {
\t\t\tbridgeResults.removeValue(forKey: nonce)
\t\t\treturn nil
\t\t}
\t\treturn result
\t}

\tprivate func acknowledgeBridgeResult(for nonce: String) -> Bool {
\t\tbridgeLock.lock()
\t\tdefer { bridgeLock.unlock() }
\t\treturn bridgeResults.removeValue(forKey: nonce) != nil
\t}

\tprivate func endBackgroundTaskIfIdle() {
\t\tbridgeLock.lock()
\t\tlet isIdle = bridgeResults.isEmpty
\t\tbridgeLock.unlock()
\t\tif isIdle { endBackgroundTask() }
\t}

\tprivate func firstAvailableBridgePort() -> Int? {
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
replace_once(old_store, new_store, "Result Store GET/ACK semantics")

replace_once(
    '\tprivate var profileURL: URL { URL(string: "http://127.0.0.1:\\(Self.port)/profile.mobileconfig")! }\n',
    '\tprivate var profileURL: URL { URL(string: "http://127.0.0.1:\\(activePort)/profile.mobileconfig")! }\n',
    "dynamic profile URL",
)

replace_once(
    '\t\treturn try? Data(contentsOf: url)\n',
    '\t\tguard let data = try? Data(contentsOf: url) else { return nil }\n'
    '\t\tguard name == "UDIDRequest", let text = String(data: data, encoding: .utf8) else { return data }\n'
    '\t\tlet updated = text.replacingOccurrences(\n'
    '\t\t\tof: "http://127.0.0.1:14302/udid",\n'
    '\t\t\twith: "http://127.0.0.1:\\(activePort)/udid"\n'
    '\t\t)\n'
    '\t\treturn Data(updated.utf8)\n',
    "dynamic Profile Service callback port",
)

path.write_text(text)

project_path = Path("HFASignBuild/Ksign.xcodeproj/project.pbxproj")
project = project_path.read_text()
old_build = "CURRENT_PROJECT_VERSION = 109;"
count = project.count(old_build)
if count != 2:
    raise SystemExit(f"build identity: expected 2 matches, found {count}")
project = project.replace(old_build, "CURRENT_PROJECT_VERSION = 110;")
project_path.write_text(project)

plist_path = Path("HFASignBuild/Ksign/Resources/Info.plist")
plist = plist_path.read_text()
old_release = "<string>v3.0.0-alphaone9</string>"
if plist.count(old_release) != 1:
    raise SystemExit(f"release identity: expected exactly one match, found {plist.count(old_release)}")
plist = plist.replace(old_release, "<string>v3.0.0-alphaone10</string>", 1)
plist_path.write_text(plist)

print("alphaone10 UDID reliability + identity transform applied")
