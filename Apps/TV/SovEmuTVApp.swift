// The Apple TV app: SovEmu.Android's TV app (`:apps:androidtv`, `:common:feature-tv`) drawn
// the tvOS way, over SovEmuKit and Apps/Shared (the same screens as the iPhone and iPad app
// wherever a TV shows them alike). Its own here: sign-in, the sidebar and the account menu.
import SwiftUI
import SovEmuKit

@main
struct SovEmuTVApp: App {
    @State private var model: AppModel
    @State private var library: Library
    @State private var settings = AppSettings()

    init() {
        let model = AppModel()
        _model = State(initialValue: model)
        _library = State(initialValue: Library(api: { [weak model] in model?.api }, signedOut: { [weak model] in model?.signedIn = false }))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(library)
                .environment(settings)
                .preferredColorScheme(.dark)
                .tint(Sov.accent)
        }
    }
}
