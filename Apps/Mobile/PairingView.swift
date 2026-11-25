import CoreImage.CIFilterBuiltins
import SwiftUI
import SovEmuKit

/// *Sign in with your phone*, as on Sovereign's TVs and SovEmu.Android: a code (and its QR code)
/// to approve at the server's `/device` page in a signed-in browser, and the poll that signs in
/// once it is. Waiting is the normal state, not an error, and is never shown as one. Leaving the
/// view cancels the poll. `onUsePassword` is nil when the server has no password sign-in.
struct PairingView: View {
    let api: SovEmuAPI
    let onSignedIn: () -> Void
    let onUsePassword: (() -> Void)?

    private enum Phase: Equatable {
        case asking
        /// `deadline` on `ProcessInfo.systemUptime`; `trouble`: the last poll got no answer.
        case showing(DeviceCode, deadline: TimeInterval, trouble: Bool)
        case failed(String)
    }

    @State private var phase = Phase.asking
    /// Bumped to ask for a new code; each one runs the request and the wait afresh.
    @State private var attempt = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(PairingText.title).font(.title2.weight(.semibold))
            switch phase {
            case .asking:
                Text(PairingText.asking).foregroundStyle(.secondary)
            case let .showing(code, deadline, trouble):
                // Side by side where there is room; the QR code under the words where there is not
                // (a phone held upright), so the code is never cut short.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 20) {
                        CodeWords(code: code)
                        QRCodeImage(text: code.qrContent).frame(width: 132, height: 132)
                            .accessibilityLabel("QR code for \(code.qrContent)")
                    }
                    VStack(alignment: .leading, spacing: 16) {
                        CodeWords(code: code)
                        QRCodeImage(text: code.qrContent).frame(width: 160, height: 160)
                            .accessibilityLabel("QR code for \(code.qrContent)")
                    }
                }
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let left = deadline - ProcessInfo.processInfo.systemUptime
                    Text("\(trouble ? PairingText.trouble : PairingText.waiting) · \(PairingText.expiresIn(left))")
                        .font(.footnote).foregroundStyle(trouble ? .orange : .secondary)
                }
            case let .failed(message):
                Text(message).foregroundStyle(.red).font(.callout)
                Button(PairingText.newCode) { attempt += 1 }
                    .buttonStyle(.borderedProminent).frame(maxWidth: .infinity)
            }
            if let onUsePassword {
                Button(PairingText.usePassword, action: onUsePassword)
                    .buttonStyle(.bordered).frame(maxWidth: .infinity)
            }
        }
        .task(id: attempt) { await pair() }
    }

    /// Asks for a code, then waits for its approval: signed in, or why not.
    @MainActor
    private func pair() async {
        phase = .asking
        let code: DeviceCode
        do {
            code = try await api.requestDeviceCode()
        } catch is CancellationError {
            return
        } catch {
            phase = .failed(error.localizedDescription)
            return
        }
        let deadline = ProcessInfo.processInfo.systemUptime + code.expiresIn
        phase = .showing(code, deadline: deadline, trouble: false)
        do {
            let result = try await awaitApproval(
                code,
                poll: { try await api.pollDeviceCode(code) },
                now: { ProcessInfo.processInfo.systemUptime },
                sleep: { try await Task.sleep(for: .seconds($0)) },
                reachable: { ok in
                    Task { @MainActor in
                        if case let .showing(c, d, _) = phase { phase = .showing(c, deadline: d, trouble: !ok) }
                    }
                })
            switch result {
            case .approved: onSignedIn()
            case let .failed(failure): phase = .failed(failure.message)
            }
        } catch {
            // Cancelled: the view went away, or a new code was asked for.
        }
    }
}

/// Where to go and the code to enter there, each on a line of its own.
private struct CodeWords: View {
    let code: DeviceCode

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(PairingText.goTo).foregroundStyle(.secondary)
            Text(code.shownURI).font(.headline).textSelection(.enabled).fixedSize()
            Text(PairingText.enter).foregroundStyle(.secondary).padding(.top, 6)
            Text(code.grouped).font(.system(size: 34, weight: .bold, design: .monospaced)).fixedSize()
                .accessibilityLabel(code.grouped.map(String.init).joined(separator: " "))
        }
    }
}

/// A QR code, sharp at any size: Core Image's generator, scaled without smoothing, dark on a
/// light margin so a phone's camera reads it.
private struct QRCodeImage: View {
    let text: String

    var body: some View {
        if let image = Self.render(text) {
            Image(decorative: image, scale: 1).interpolation(.none).resizable().scaledToFit()
                .padding(8).background(.white, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private static let context = CIContext()

    static func render(_ text: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        return context.createCGImage(output, from: output.extent)
    }
}
