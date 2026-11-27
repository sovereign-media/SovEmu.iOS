// The TV's account screens, as SovEmu.Android's TV app draws them (`feature-tv`'s `Accounts.kt`,
// `CustomHeaders.kt`): *Who's watching?*, *Choose a server* and the proxy headers. The sign-in
// form and *Sign in with your phone* are `SignInPages.swift`; the stack is `ConnectView.swift`.
import SovEmuKit
import SwiftUI


// MARK: - Who's watching?

/// A tile per account on this server, then *Add user* (hidden at `StoredAccount.maxPerServer`),
/// three to a row, each row centred; under them *Change server* with the server beside it. Focus
/// starts on `focusOn` (the account used last, or the one signed in now when opened from the
/// account menu, whose tile reads *Signed in now*: `current`).
struct WhoIsWatchingPage: View {
    let accounts: [StoredAccount]
    let server: String
    let focusOn: String?
    let current: String?
    let onChoose: (StoredAccount) -> Void
    let onAddUser: () -> Void
    let onChangeServer: () -> Void
    @FocusState private var focus: Int?

    private static let tile: CGFloat = 128

    var body: some View {
        let canAdd = accounts.count < StoredAccount.maxPerServer
        let tiles: [StoredAccount?] = accounts + (canAdd ? [nil] : [])
        let columns = LaunchText.pickerColumns
        let rows = stride(from: 0, to: tiles.count, by: columns).map { Array(tiles[$0..<min($0 + columns, tiles.count)]) }
        LaunchBackdrop {
            Text(LaunchText.whoIsWatching)
                .font(.system(size: 32 * launchDp, weight: .bold)).foregroundStyle(.white)
                .padding(.bottom, 24 * launchDp)
            ForEach(rows.indices, id: \.self) { row in
                HStack(spacing: 24 * launchDp) {
                    ForEach(rows[row].indices, id: \.self) { column in
                        let index = row * columns + column
                        tileButton(rows[row][column]).focused($focus, equals: index)
                    }
                }
                .padding(.bottom, 16 * launchDp)
            }
            HStack(spacing: 12 * launchDp) {
                Button(action: onChangeServer) { Label(LaunchText.changeServer, systemImage: "server.rack") }
                    .buttonStyle(.launch(.ghost))
                Text(server).font(.system(size: 14 * launchDp)).foregroundStyle(Sov.slate500).lineLimit(1).truncationMode(.middle)
            }
            .frame(maxWidth: 480 * launchDp)
            .padding(.top, 8 * launchDp)
        }
        .defaultFocus($focus, max(0, accounts.firstIndex { $0.id == focusOn } ?? 0))
    }

    @ViewBuilder private func tileButton(_ account: StoredAccount?) -> some View {
        Button {
            if let account { onChoose(account) } else { onAddUser() }
        } label: {
            AccountTile(account: account, size: Self.tile, caption: account?.id == current && current != nil ? LaunchText.signedInNow : nil)
        }
        .buttonStyle(LaunchCardStyle(corner: 16))
    }
}

/// An account's disc (its initials) and name; nil: *Add user*'s.
private struct AccountTile: View {
    let account: StoredAccount?
    let size: CGFloat
    let caption: String?

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if account == nil {
                    Circle().stroke(Sov.edge, lineWidth: 2 * launchDp)
                    Image(systemName: "person.badge.plus").font(.system(size: size / 3 * launchDp)).foregroundStyle(Sov.slate300)
                } else {
                    Circle().fill(LinearGradient(colors: [Sov.accent, Color(hex: 0x1E3A8A)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Text(account?.initials ?? "").font(.system(size: size / 3 * launchDp, weight: .bold)).foregroundStyle(.white)
                }
            }
            .frame(width: size * launchDp, height: size * launchDp)
            Text(account?.label ?? LaunchText.addUser)
                .font(.system(size: 16 * launchDp)).foregroundStyle(Sov.slate100).lineLimit(1)
                .padding(.top, 10 * launchDp)
            if let caption {
                Text(caption).font(.system(size: 12 * launchDp)).foregroundStyle(Sov.slate500)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12 * launchDp)
        .frame(width: (size + 24) * launchDp, height: (size + 88) * launchDp)
        .contentShape(Rectangle())
    }
}

// MARK: - Choose a server

/// Every server the device holds an account for, the one in use marked; choosing one moves the
/// app there, and each row's *Remove* asks first, naming everyone it signs out (Cancel has the
/// focus, Back cancels). *Add a server* opens the form for a new address; at
/// `StoredAccount.maxServers` its place says how to free one.
struct ChooseServerPage: View {
    let servers: [KnownServer]
    let error: String?
    let busy: Bool
    let onChoose: (KnownServer) -> Void
    let onRemove: (KnownServer) -> Void
    let onAddServer: () -> Void
    @State private var confirming: KnownServer?
    @FocusState private var focus: Int?

    var body: some View {
        ZStack {
            LaunchBackdrop {
                Text(KnownServers.title).font(.system(size: 26 * launchDp, weight: .bold)).foregroundStyle(.white)
                Text(KnownServers.hint).font(.system(size: 14 * launchDp)).foregroundStyle(launchMuted)
                    .padding(.top, 4 * launchDp).padding(.bottom, 20 * launchDp)
                VStack(spacing: 10 * launchDp) {
                    ForEach(Array(servers.enumerated()), id: \.element.key) { i, server in
                        HStack(spacing: 8 * launchDp) {
                            Button { if !busy { onChoose(server) } } label: { row(server) }
                                .buttonStyle(LaunchCardStyle())
                                .focused($focus, equals: i)
                            Button { if !busy { confirming = server } } label: {
                                Label(KnownServers.remove, systemImage: "trash")
                            }
                            .buttonStyle(.launch(.ghost))
                        }
                    }
                    if let error { LaunchErrorLine(error) }
                    if KnownServers.canAddServer(servers.count) {
                        Button { if !busy { onAddServer() } } label: { Label(KnownServers.addAServer, systemImage: "server.rack") }
                            .buttonStyle(.launch(.outline, fill: true))
                            .padding(.top, 6 * launchDp)
                    } else {
                        Text(KnownServers.capLine).font(.system(size: 14 * launchDp)).foregroundStyle(Sov.slate500)
                    }
                }
                .frame(width: 560 * launchDp)
            }
            .disabled(confirming != nil)
            if let server = confirming {
                RemoveServerConfirm(server: server, onCancel: { confirming = nil }, onRemove: {
                    confirming = nil
                    onRemove(server)
                })
            }
        }
        .defaultFocus($focus, 0)
    }

    private func row(_ server: KnownServer) -> some View {
        HStack(spacing: 14 * launchDp) {
            Image(systemName: "server.rack").font(.system(size: 22 * launchDp)).foregroundStyle(Sov.slate300)
            VStack(alignment: .leading, spacing: 2 * launchDp) {
                Text(server.address).font(.system(size: 16 * launchDp)).foregroundStyle(Sov.slate100).lineLimit(1)
                Text(server.countLine).font(.system(size: 13 * launchDp)).foregroundStyle(Sov.slate500)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16 * launchDp)
        .frame(maxWidth: .infinity, minHeight: 72 * launchDp, maxHeight: 72 * launchDp)
        .background(Sov.panel)
    }
}

/// Asks before removing `server`, naming everyone it signs out: Cancel has the focus, and Back
/// cancels.
private struct RemoveServerConfirm: View {
    let server: KnownServer
    let onCancel: () -> Void
    let onRemove: () -> Void
    @FocusState private var cancel: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 16 * launchDp) {
                Text(server.removeTitle).font(.system(size: 20 * launchDp, weight: .bold)).foregroundStyle(.white)
                Text(server.removeMessage).font(.system(size: 15 * launchDp)).foregroundStyle(Sov.slate300)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12 * launchDp) {
                    Button(KnownServers.cancel, action: onCancel).buttonStyle(.launch(.outline)).focused($cancel)
                    Button(action: onRemove) { Label(KnownServers.remove, systemImage: "trash") }.buttonStyle(.launch())
                }
            }
            .padding(28 * launchDp)
            .frame(width: 440 * launchDp, alignment: .leading)
            .background(Sov.panel, in: RoundedRectangle(cornerRadius: 16 * launchDp))
            .overlay(RoundedRectangle(cornerRadius: 16 * launchDp).stroke(Sov.edge, lineWidth: launchDp))
            .focusSection()
        }
        .defaultFocus($cancel, true)
        .onAppear { cancel = true }
        .onExitCommand(perform: onCancel)
    }
}

// MARK: - Custom headers

/// The words of the custom headers screen, as Android's `CustomHeadersText`.
enum CustomHeadersText {
    static let title = "Custom headers"
    static let hint = "Sent with every request to this server, for a proxy in front of it (Cloudflare Access and the like)."
    static let add = "Add a header"
    static let name = "Name"
    static let value = "Value"
    static let save = "Save"
    static let remove = "Remove"
    static let cancel = "Cancel"
    static let done = "Done"
    /// What a row shows for a value: it is usually a credential.
    static let hidden = "••••••"
}

/// The proxy headers sent with every request to the server: listed by name (values hidden), each
/// opening a form to change or remove it, and *Add a header* until there are
/// `CustomHeaderRules.maxHeaders`. The rules are checked before a save, and say what to fix. Back
/// from the form goes back to the list.
struct CustomHeadersPage: View {
    @Binding var headers: [CustomHeader]
    let onDone: () -> Void
    /// The row being changed: -1 for a new header, nil while the list shows.
    @State private var editing: Int?
    @State private var name = ""
    @State private var value = ""
    @State private var error: String?
    @FocusState private var focus: Int?
    @FocusState private var field: LaunchFocus?

    var body: some View {
        LaunchBackdrop {
            VStack(alignment: .leading, spacing: 12 * launchDp) {
                Text(CustomHeadersText.title).font(.system(size: 26 * launchDp, weight: .bold)).foregroundStyle(.white)
                Text(CustomHeadersText.hint).font(.system(size: 14 * launchDp)).foregroundStyle(launchMuted)
                    .fixedSize(horizontal: false, vertical: true)
                if let row = editing { form(row) } else { list }
            }
            .frame(width: 480 * launchDp)
        }
        .onExitCommand(perform: editing == nil ? onDone : { editing = nil })
        .defaultFocus($focus, headers.isEmpty ? -1 : 0)
        .defaultFocus($field, .name)
    }

    @ViewBuilder private var list: some View {
        ForEach(Array(headers.enumerated()), id: \.offset) { i, header in
            Button { open(i) } label: {
                HStack {
                    Text(header.name).font(.system(size: 16 * launchDp)).foregroundStyle(Sov.slate100).lineLimit(1)
                    Spacer()
                    Text(CustomHeadersText.hidden).font(.system(size: 16 * launchDp)).foregroundStyle(Sov.slate500)
                }
                .padding(.horizontal, 16 * launchDp)
                .frame(maxWidth: .infinity, minHeight: 60 * launchDp, maxHeight: 60 * launchDp)
                .background(Sov.panel)
            }
            .buttonStyle(LaunchCardStyle())
            .focused($focus, equals: i)
        }
        if headers.count < CustomHeaderRules.maxHeaders {
            Button(CustomHeadersText.add) { open(-1) }
                .buttonStyle(.launch(.outline, fill: true))
                .focused($focus, equals: -1)
        }
        Button(CustomHeadersText.done, action: onDone).buttonStyle(.launch(fill: true))
    }

    @ViewBuilder private func form(_ row: Int) -> some View {
        LaunchField(CustomHeadersText.name, text: $name, keyboard: .URL, focus: $field, tag: .name)
            .onChange(of: name) { error = nil }
        LaunchField(CustomHeadersText.value, text: $value, keyboard: .asciiCapable)
            .onChange(of: value) { error = nil }
        if let error { LaunchErrorLine(error) }
        HStack(spacing: 12 * launchDp) {
            Button(CustomHeadersText.save) {
                let n = CustomHeaderRules.cleanName(name)
                let v = CustomHeaderRules.cleanValue(value)
                error = CustomHeaderRules.validate(headers, name: n, value: v, replaceIndex: row)
                if error == nil {
                    headers = CustomHeaderRules.upsert(headers, name: n, value: v, replaceIndex: row)
                    editing = nil
                }
            }
            .buttonStyle(.launch())
            if row >= 0 {
                Button(CustomHeadersText.remove) {
                    headers = CustomHeaderRules.removeAt(headers, row)
                    editing = nil
                }
                .buttonStyle(.launch(.outline))
            }
            Button(CustomHeadersText.cancel) { editing = nil }.buttonStyle(.launch(.ghost))
        }
    }

    private func open(_ index: Int) {
        editing = index
        name = headers.indices.contains(index) ? headers[index].name : ""
        value = headers.indices.contains(index) ? headers[index].value : ""
        error = nil
    }
}
