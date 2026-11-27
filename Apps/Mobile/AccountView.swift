import SwiftUI
import SovEmuKit

/// The account and the app's settings, as the other clients' account menu.
struct AccountView: View {
    @Environment(AppModel.self) private var model
    @Environment(Library.self) private var library
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                LabeledContent("Signed in as", value: library.user?.username ?? "…")
                LabeledContent("Server", value: model.serverURL)
            }
            Section {
                Toggle(isOn: $settings.music) { Label("Music", systemImage: "music.note") }
                Picker(selection: $settings.screensaverMinutes) {
                    ForEach(AppSettings.screensaverChoices, id: \.self) { minutes in
                        Text(minutes == 0 ? "Off" : "After \(minutes) min").tag(minutes)
                    }
                } label: {
                    Label("Screensaver", systemImage: "play.rectangle")
                }
                Toggle(isOn: $settings.scanlines) { Label("Scan lines", systemImage: "line.3.horizontal") }
            } footer: {
                Text("The screensaver plays games' videos after a while without a touch or a button press, and keeps the screen awake in the menus until then. Music follows the silent switch.")
            }
            Section {
                // A TV signs itself in with a code; this approves one from here.
                NavigationLink {
                    SignInTVView()
                } label: {
                    Label(TvSignIn.title, systemImage: "tv")
                }
            }
            Section {
                Button(role: .destructive) {
                    Task { await model.signOut() }
                } label: {
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
        .plainListBackground()
        .background(Sov.surface)
        .navigationTitle(library.user?.username ?? "Account")
    }
}
