// The account menu, as SovEmu.Android's TV app's (`Nav.kt`): who is signed in, the app's
// settings (music, the screensaver, scan lines), and changing the server or signing out.
import SwiftUI
import SovEmuKit

struct TVAccountView: View {
    @Environment(AppModel.self) private var model
    @Environment(TVSession.self) private var session
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
                Text("The screensaver plays games' videos after a while without a button press.")
            }
            Section {
                Button {
                    session.changeUserOrServer()
                } label: {
                    Label(LaunchText.changeUserOrServer, systemImage: "person.2")
                }
                Button(role: .destructive) {
                    Task { await session.signOut() }
                } label: {
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
        .navigationTitle(library.user?.username ?? "Account")
    }
}
