import SwiftUI

@main
struct StacksApp: App {
    @StateObject private var session = AppSession()

    var body: some Scene {
        WindowGroup {
            Group {
                if let client = session.client {
                    HomeView(client: client)
                } else {
                    LoginView()
                }
            }
            .environmentObject(session)
            .tint(.orange)
        }
    }
}
