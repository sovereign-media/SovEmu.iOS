import SwiftUI
import SovEmuKit

@main
struct SovEmuApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.dark)
        }
    }
}

/// The server address (kept across launches) and the API client for it. The sign-in cookie
/// lives in the shared cookie storage.
@Observable
final class AppModel {
    var serverURL: String = UserDefaults.standard.string(forKey: "server") ?? "" {
        didSet { UserDefaults.standard.set(serverURL, forKey: "server") }
    }
    var signedIn = false

    var api: SovEmuAPI? {
        URL(string: serverURL.trimmingCharacters(in: .whitespaces)).map { SovEmuAPI(baseURL: $0) }
    }
}

enum Route: Hashable {
    case games(SystemSummary)
    case play(SystemSummary, Game)
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var path: [Route] = []
    @State private var checked = false

    var body: some View {
        Group {
            if !checked {
                ProgressView()
            } else if !model.signedIn {
                ConnectView()
            } else {
                NavigationStack(path: $path) {
                    SystemsView(path: $path)
                        .navigationDestination(for: Route.self) { route in
                            switch route {
                            case .games(let system):
                                GamesView(system: system, path: $path)
                            case .play(let system, let game):
                                PlayerView(system: system, game: game) { path.removeLast() }
                                    .toolbar(.hidden, for: .navigationBar)
                            }
                        }
                }
            }
        }
        .task {
            if let api = model.api, let status = try? await api.status() {
                model.signedIn = status.user != nil
            }
            checked = true
        }
    }
}

extension SystemSummary {
    var accent: Color {
        let (r, g, b) = rgb
        return Color(red: r, green: g, blue: b)
    }
}
