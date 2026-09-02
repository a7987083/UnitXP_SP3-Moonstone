import SwiftUI

@main
struct HFAPatchIPAApp: App {
    @StateObject private var model = WorkspaceModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
        }
    }
}
