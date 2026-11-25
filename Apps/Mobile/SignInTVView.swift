import SwiftUI
import SovEmuKit

/// *Sign in a TV* (Sovereign's `clients-sign-in-a-tv.md`, as SovEmu.Android's): type the code a
/// TV's *Sign in with your phone* screen shows, confirm, and the TV signs in as this account. An
/// error keeps the code, so a typo is fixed rather than typed again; approval is never automatic.
struct SignInTVView: View {
    @Environment(AppModel.self) private var model
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    /// Kept as typed: it is normalised only to check it and to send it.
    @State private var code = ""
    @State private var confirming = false
    @State private var sending = false
    @State private var approved = false
    @State private var error: String?

    var body: some View {
        Form {
            if approved {
                Text(TvSignIn.approved)
            } else {
                Section {
                    TextField(TvSignIn.fieldLabel, text: $code)
                        .font(.system(.title3, design: .monospaced))
                        .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    if let error { Text(error).foregroundStyle(.red).font(.callout) }
                } header: {
                    Text(TvSignIn.intro)
                }
                Button(TvSignIn.continueLabel) { confirming = true; error = nil }
                    .disabled(!TvSignIn.isComplete(code) || sending)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Sov.surface)
        .navigationTitle(TvSignIn.title)
        .confirmationDialog(
            TvSignIn.confirmation(server: model.serverURL, name: library.user?.username ?? ""),
            isPresented: $confirming, titleVisibility: .visible
        ) {
            Button(TvSignIn.approve) { Task { await approve() } }
            Button(TvSignIn.cancel, role: .cancel) {}
        }
    }

    private func approve() async {
        guard let api = model.api else { return }
        sending = true
        defer { sending = false }
        do {
            try await api.approveDeviceCode(TvSignIn.format(code))
            approved = true
            // The approved line shows for a moment, then back to the account.
            try? await Task.sleep(for: .seconds(1.5))
            dismiss()
        } catch {
            self.error = TvSignIn.failure(error)
        }
    }
}
