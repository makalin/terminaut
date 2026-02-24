import SwiftUI

@main
struct TerminautApp: App {
    @StateObject private var state: AppState

    init() {
        if let client = try? RustCoreClient() {
            _state = StateObject(wrappedValue: AppState(coreClient: client))
        } else {
            _state = StateObject(wrappedValue: AppState(coreClient: FallbackCoreClient()))
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(state)
                .navigationTitle("Terminaut")
                .task {
                    state.bootstrap()
                }
        }
        .windowResizability(.contentSize)
    }
}
