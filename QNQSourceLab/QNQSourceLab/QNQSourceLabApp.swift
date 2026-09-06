import SwiftUI

@main
struct QNQSourceLabApp: App {
    init() {
        Self.installBundledV2KeyIfPresent()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }

    private static func installBundledV2KeyIfPresent() {
        guard let sourceURL = Bundle.main.url(forResource: "appstore_v2", withExtension: "pem") else {
            return
        }
        guard let data = try? Data(contentsOf: sourceURL), !data.isEmpty else {
            return
        }
        let documentDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let targetURL = documentDirectory.appendingPathComponent("appstore_v2.pem")
        try? data.write(to: targetURL, options: .atomic)
    }
}
