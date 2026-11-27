// The Apple TV app: SovEmu.Android's TV app (`:apps:androidtv`, `:common:feature-tv`) drawn
// the tvOS way, over SovEmuKit and Apps/Shared.
import SwiftUI
import SovEmuKit

@main
struct SovEmuTVApp: App {
    var body: some Scene {
        WindowGroup {
            Text("SovEmu")
                .preferredColorScheme(.dark)
                .tint(Sov.accent)
        }
    }
}
