import Foundation
import Synchronization
import Testing
@testable import SovEmuKit

/// The GraphQL requests the client sends through Apollo and how it reads the answers, against a
/// stub server. The documents themselves are checked against the schema by codegen
/// (`scripts/codegen.sh`); these pin what the app does with them.
struct APITests {
    /// An API on a stub that answers every `/graphql` request with `answer`, and the bodies it was sent.
    private func api(_ answer: @escaping @Sendable () -> (Int, String)) -> (SovEmuAPI, Bodies) {
        let bodies = Bodies()
        let stub = Stub { _, body in
            bodies.add(body)
            return answer()
        }
        return (SovEmuAPI(baseURL: stub.base, session: stub.session), bodies)
    }

    private func api(_ json: String, status: Int = 200) -> (SovEmuAPI, Bodies) { api { (status, json) } }

    @Test func postsTheOperationToGraphql() async throws {
        let bodies = Bodies()
        let stub = Stub { request, body in
            bodies.add(body)
            #expect(request.authorization == nil, "an API with no sign-in sends no token")
            #expect(request.cookie == nil, "the API authenticates with tokens, never cookies")
            return (200, #"{"data":{"system":{"games":[]}}}"#)
        }
        let api = SovEmuAPI(baseURL: stub.base, session: stub.session)
        #expect(try await api.games(system: "nes").isEmpty)
        #expect(stub.requests.map(\.path) == ["/graphql"])
        let body = try bodies.only()
        #expect(body["operationName"] as? String == "SystemGames")
        #expect((body["query"] as? String)?.contains("system(id: $id)") == true)
        #expect(body["variables"] as? [String: String] == ["id": "nes"])
    }

    @Test func sendsNumbersAsNumbersAndNoneAsAnExplicitNull() async throws {
        let (api, bodies) = api(#"{"data":{"setPatch":true}}"#)
        try await api.setPatch(gameId: 7, patchId: nil)
        let variables = try #require(try bodies.only()["variables"] as? [String: Any])
        #expect(variables["gameId"] as? Int == 7)
        // The original game is an explicit null, never a missing argument.
        #expect(variables["patchId"] is NSNull)
    }

    @Test func theOfferNamesTheClient() async throws {
        let (api, bodies) = api(#"{"data":{"sessionOffer":"v=0\r\n"}}"#)
        #expect(try await api.offer(sessionId: "s1", sdp: "v=0", client: "ios 0.1.0 (iPhone, iOS 26.0)") == "v=0\r\n")
        _ = try await api.offer(sessionId: "s1", sdp: "v=0")
        let sent = try bodies.all.map { try #require($0["variables"] as? [String: Any]) }
        #expect(sent[0]["id"] as? String == "s1" && sent[0]["sdp"] as? String == "v=0")
        #expect(sent[0]["client"] as? String == "ios 0.1.0 (iPhone, iOS 26.0)")
        #expect(sent[1]["client"] is NSNull)
    }

    @Test func readsTheViewerAndAnUnknownRoleAsAViewer() async throws {
        let admin = try await api("""
            {"data":{"viewer":{"setupRequired":false,"user":{"id":1,"username":"ada","isAdmin":true,"role":"ADMIN"}}}}
            """).0.status()
        #expect(admin.user == User(id: 1, username: "ada", isAdmin: true, role: .admin))
        let newer = try await api("""
            {"data":{"viewer":{"setupRequired":false,"user":{"id":3,"username":"cy","isAdmin":false,"role":"GUEST"}}}}
            """).0.status()
        #expect(newer.user?.role == .viewer, "a role a newer server adds grants no more than viewing")
        let setup = try await api(#"{"data":{"viewer":{"setupRequired":true,"user":null}}}"#).0.status()
        #expect(setup.setupRequired && setup.user == nil)
    }

    @Test func readsSystems() async throws {
        let systems = try await api("""
            {"data":{"systems":[{"id":"nes","name":"Nintendo Entertainment System","short":"NES",
             "manufacturer":"Nintendo","year":1983,"color":"#c0392b","gameCount":2,"playable":true,
             "needsGpu":false,"rendering":null,"biosMissing":false,"boxAspect":0.72},
             {"id":"n64","name":"Nintendo 64","short":"N64","manufacturer":"Nintendo","year":1996,
             "color":"#2c3e50","gameCount":0,"playable":true,"needsGpu":true,"rendering":"SOFTWARE",
             "biosMissing":true,"boxAspect":1.38}]}}
            """).0.systems()
        #expect(systems[0].gameCount == 2 && systems[0].boxAspect == 0.72)
        #expect(systems[0].rgb.0 > 0.75 && systems[0].rgb.2 < 0.25)
        #expect(systems[1].needsGpu && systems[1].rendering == "SOFTWARE" && systems[1].biosMissing)
    }

    @Test func readsGamesAndTellsAMissingSystem() async throws {
        let games = try await api("""
            {"data":{"system":{"games":[\(Self.game(id: 7, extra: #""partKind":"CASSETTE","esrb":"AO_NEW""#))]}}}
            """).0.games(system: "nes")
        let game = try #require(games.first)
        #expect(game.id == 7 && game.tags == ["USA", "Rev 1"] && game.size == 40976)
        #expect(game.autoSave == SaveSlot(slot: 0, savedAt: 1_700_000_000, screenshotUrl: "/media/s.png"))
        #expect(game.partKind == .disc, "a kind a newer server adds is drawn as a disc")
        #expect(game.esrb == nil, "a rating a newer server adds is no rating")

        let missing = await #expect(throws: APIError.self) {
            try await api(#"{"data":{"system":null}}"#).0.games(system: "nope")
        }
        #expect(missing?.code == "NOT_FOUND")
    }

    @Test func readsTheHomeFeed() async throws {
        let feed = try await api("""
            {"data":{"home":{"featured":[\(Self.game(id: 1))],"recent":[],"added":[\(Self.game(id: 2))],
             "topRated":[],"favourites":[]},"collections":[{"id":4,"name":"Couch","games":[\(Self.game(id: 3))]}]}}
            """).0.home()
        #expect(feed.featured.map(\.id) == [1] && feed.added.map(\.id) == [2])
        #expect(feed.collections == [HomeCollection(id: 4, name: "Couch", games: [feed.collections[0].games[0]])])
        #expect(feed.collections[0].games.map(\.id) == [3])
    }

    @Test func readsSessionsAndTheirDiscs() async throws {
        let session = try await api("""
            {"data":{"startSession":{"id":"x","gameId":8,"system":"psx","title":"Epic","core":"PCSX-ReARMed",
             "width":256,"height":240,"fps":60.0,"connected":false,"discs":2,"disc":1}}}
            """).0.startSession(gameId: 8)
        #expect(session.id == "x" && session.gameId == 8 && !session.connected)
        #expect(session.discs == 2 && session.disc == 1)
    }

    @Test func readsTheIceServersFromTheJsonScalar() async throws {
        // `iceServers` is a JSON scalar holding `RTCIceServer` objects, whose `urls` is one or many.
        let config = try await api("""
            {"data":{"clientConfig":{"iceServers":[{"urls":"stun:a"},
             {"urls":["turn:b","turns:c"],"username":"u","credential":"p"}]}}}
            """).0.config()
        #expect(config.iceServers.map(\.urls) == [["stun:a"], ["turn:b", "turns:c"]])
        #expect(config.iceServers[1].username == "u" && config.iceServers[1].credential == "p")
    }

    @Test func sendsAndReadsControllerMappings() async throws {
        let (api, bodies) = api("""
            {"data":{"saveControllerMapping":{"controller":"dualsense","system":"megadrive","name":"DualSense",
             "bindings":[{"input":"south","button":"A"}],"source":"USER"}}}
            """)
        let saved = try await api.saveControllerMapping(
            controller: "dualsense", system: "megadrive", name: "DualSense",
            bindings: [ControllerBinding(input: "south", button: "A"), ControllerBinding(input: "east", button: "B")])
        #expect(saved == ControllerMapping(
            controller: "dualsense", system: "megadrive", name: "DualSense",
            bindings: [ControllerBinding(input: "south", button: "A")], source: .user))
        // Bindings go as a list of objects with the schema's field names.
        let sent = try #require(try bodies.only()["variables"] as? [String: Any])
        #expect(sent["controller"] as? String == "dualsense" && sent["system"] as? String == "megadrive")
        #expect(sent["bindings"] as? [[String: String]] == [["input": "south", "button": "A"], ["input": "east", "button": "B"]])

        let mappings = try await self.api("""
            {"data":{"controllerMappings":[{"controller":"keyboard","system":null,"name":"Keyboard",
             "bindings":[{"input":"KeyP","button":"START"}],"source":"USER"},
             {"controller":"xbox","system":"megadrive","name":"Xbox","bindings":[],"source":"ENVIRONMENT"},
             {"controller":"dualsense","system":null,"name":"DualSense","bindings":[],"source":"SOMETHING_NEW"}]}}
            """).0.controllerMappings(system: nil)
        #expect(mappings.map(\.source) == [.user, .environment, .admin], "a source a newer server adds is a default")
        #expect(mappings.map(\.system) == [nil, "megadrive", nil])
        #expect(!mappings[0].source.isDefault && mappings[1].source.isDefault)
    }

    @Test func sendsEverySystemAsAnExplicitNull() async throws {
        let (api, bodies) = api(#"{"data":{"resetControllerMapping":false}}"#)
        #expect(try await api.resetControllerMapping(controller: "xbox", system: nil) == false)
        let sent = try #require(try bodies.only()["variables"] as? [String: Any])
        #expect(sent["controller"] as? String == "xbox")
        #expect(sent["system"] is NSNull)
        #expect(MappingScope.system("megadrive").systemArgument == "megadrive")
        #expect(MappingScope.everySystem.systemArgument == nil)
    }

    @Test func sendsClientEventsAsTheSchemasInput() async throws {
        let bodies = Bodies()
        let stub = Stub { request, body in
            guard request.path == "/graphql" else { return Stub.tokens("a", "r") }
            bodies.add(body)
            return (200, #"{"data":{"reportClientEvents":1}}"#)
        }
        let auth = TokenClient(baseURL: stub.base, endpoints: stub.endpoints, store: MemoryTokenStore(), session: stub.session)
        try await auth.signIn(username: "ada", password: "pw")
        let api = SovEmuAPI(baseURL: stub.base, auth: auth, session: stub.session)
        let events = [ClientEvent(kind: .streamStalled, message: "no frames for 3 s", sessionId: "s1", at: 1_700_000_000.5)]
        #expect(try await api.reportClientEvents(client: "ios 0.1.0", events: events) == 1)
        let variables = try #require(try bodies.only()["variables"] as? [String: Any])
        #expect(variables["client"] as? String == "ios 0.1.0")
        let sent = try #require(variables["events"] as? [[String: Any]])
        #expect(sent.count == 1 && sent[0]["kind"] as? String == "STREAM_STALLED")
        #expect(sent[0]["message"] as? String == "no frames for 3 s" && sent[0]["sessionId"] as? String == "s1")
        #expect(sent[0]["at"] as? Double == 1_700_000_000.5)
        #expect(try await api.reportClientEvents(client: "ios", events: []) == 0, "nothing to report sends nothing")
    }

    @Test func readsASystemsControlsAndTheControllersDiagrams() async throws {
        let info = try await api(Fixtures.megadriveControls).0.controls(system: "megadrive")
        let controls = try #require(info.controls)
        // The Mega Drive's A, B and C are RetroPad Y, B and A.
        let labels = Dictionary(uniqueKeysWithValues: controls.buttons.map { ($0.button, $0.label) })
        #expect(labels["Y"] == "A" && labels["B"] == "B" && labels["A"] == "C")
        #expect(controls.buttons.prefix(4).map(\.button) == ["UP", "DOWN", "LEFT", "RIGHT"], "directions first")
        // Lists name the D-pad in words; the diagram draws arrows. Both come from the server.
        #expect(controls.buttons.prefix(4).map(\.label) == ["Up", "Down", "Left", "Right"])
        #expect(controls.layout.keys.first { $0.key == "UP" }?.label == "↑")
        #expect(controls.buttons.allSatisfy { $0.retroButton != nil })
        #expect(controls.sticks.isEmpty, "a Mega Drive pad has no sticks")
        #expect(controls.layout.id == "megadrive" && controls.layout.width == 160 && controls.layout.height == 100)
        #expect(Set(controls.layout.keys.map(\.key)) == Set(controls.buttons.map(\.button)), "every button is drawn")

        #expect(info.controllerLayouts.map(\.id) == ["xbox", "playstation", "nintendo", "generic"])
        let ps = try #require(info.layout(for: .playstation))
        #expect(ps.keys.first { $0.key == "south" }?.label == "✕")
        #expect(Set(ps.keys.map(\.key)) == Set(PadInput.allCases.map(\.rawValue)))
        let shape = try #require(ps.body.first)
        #expect(shape.tone == 0 && shape.r > 0)

        // An unknown system has no controls; the controllers' diagrams still come.
        let none = try await api(#"{"data":{"system":null,"controllerLayouts":[]}}"#).0.controls(system: "nope")
        #expect(none.controls == nil && none.layout(for: .xbox) == nil)
    }

    @Test func readsASystemsSticks() throws {
        let json = #"{"buttons":[],"sticks":[{"stick":"LEFT","label":"Control stick","key":"LS"},{"stick":"RIGHT","label":"C buttons","key":"RS"}],"layout":{"id":"n64","name":"Nintendo 64","width":160.0,"height":100.0,"body":[],"keys":[]}}"#
        let controls = try JSONDecoder().decode(SystemControls.self, from: Data(json.utf8))
        let sticks = remapSticks(controls, scope: .system("n64"))
        #expect(sticks.map(\.label) == ["Control stick", "C buttons"])
        #expect(sticks.map(\.stickName) == ["Left stick", "Right stick"])
        // A stick's row lights its control on the system's pad and the stick on the controller's.
        let lit = DiagramHighlight(stick: sticks[1])
        #expect(lit.systemKeys == ["RS"] && lit.controllerKeys == ["r3"])
        #expect(remapSticks(controls, scope: .everySystem).isEmpty, "only in the system's own scope")
    }

    @Test func cropsDiagramsToWhatIsDrawn() async throws {
        let info = try await api(Fixtures.megadriveControls).0.controls(system: "megadrive")
        // The Mega Drive's body is (10, 28, 140, 52), its Mode key tops out at y 23.
        let md = try #require(info.controls?.layout).visibleBounds
        #expect(md.x == 7 && md.y == 20 && md.w == 146 && md.h == 63)
        // Never past the canvas, and the whole canvas when nothing is drawn.
        let edge = PadLayout(id: "t", name: "t", body: [PadShape(x: 1, y: 90, w: 159, h: 10, r: 0)], keys: [])
        #expect(edge.visibleBounds == (0, 87, 160, 13))
        #expect(PadLayout(id: "t", name: "t", body: [], keys: []).visibleBounds == (0, 0, 160, 100))
    }

    @Test func throwsTheFirstErrorWithItsCode() async throws {
        let unauthenticated = await #expect(throws: APIError.self) {
            try await api("""
                {"data":null,"errors":[{"message":"sign in first","locations":[{"line":1,"column":17}],
                 "path":["systems"],"extensions":{"code":"UNAUTHENTICATED"}}]}
                """).0.systems()
        }
        #expect(unauthenticated?.code == "UNAUTHENTICATED" && unauthenticated?.isUnauthenticated == true)
        #expect(unauthenticated?.localizedDescription == "sign in first")

        let notFound = await #expect(throws: APIError.self) {
            try await api(#"{"data":null,"errors":[{"message":"no such game","extensions":{"code":"NOT_FOUND"}}]}"#)
                .0.startSession(gameId: 1)
        }
        #expect(notFound?.code == "NOT_FOUND" && notFound?.isUnauthenticated == false)

        // An error without extensions still carries its message.
        let plain = await #expect(throws: APIError.self) {
            try await api(#"{"data":null,"errors":[{"message":"boom"}]}"#).0.stopSession("s1")
        }
        #expect(plain?.code == nil && plain?.message == "boom")
    }

    @Test func reportsHttpFailuresAndUnreadableAnswers() async throws {
        let gateway = await #expect(throws: APIError.self) { try await api("<html>", status: 502).0.stopSession("s1") }
        #expect(gateway?.status == 502 && gateway?.code == nil)
        // A 4xx with a GraphQL body keeps the server's message and code.
        let refused = await #expect(throws: APIError.self) {
            try await api(#"{"errors":[{"message":"too big","extensions":{"code":"BAD_REQUEST"}}]}"#, status: 400).0.stopSession("s1")
        }
        #expect(refused?.status == 400 && refused?.code == "BAD_REQUEST" && refused?.message == "too big")
        // An answer that does not fit the schema.
        let odd = await #expect(throws: APIError.self) { try await api(#"{"data":{"stopSession":"yes"}}"#).0.stopSession("s1") }
        #expect(odd?.status == 200)
        #expect(APIError(status: 401, message: "").isUnauthenticated)
    }

    /// A game as `GameFields` selects it, with `extra` (JSON object members, `"title":"X"`)
    /// replacing the defaults.
    static func game(id: Int, extra: String = "") -> String {
        let defaults = """
            {"id":\(id),"system":"nes","title":"Alter Ego","fileTitle":null,"tags":["USA","Rev 1"],"path":"Alter Ego.nes",
             "size":40976.0,"lastPlayedAt":null,"playCount":0,"image":null,"imageSmall":null,"cover":null,"thumb":null,
             "video":null,"description":null,"releaseDate":null,"developer":null,"publisher":null,"genre":null,"genres":[],
             "players":null,"rating":null,"esrb":null,"esrbBadgeUrl":null,"modes":[],"series":[],"themes":[],"discs":1,
             "partKind":null,"favourite":false,"release":null,"patch":null,
             "autoSave":{"slot":0,"savedAt":1700000000,"screenshotUrl":"/media/s.png"}}
            """
        func object(_ json: String) -> [String: Any] {
            (try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]) ?? [:]
        }
        let merged = object(defaults).merging(object("{\(extra)}")) { $1 }
        return String(decoding: try! JSONSerialization.data(withJSONObject: merged), as: UTF8.self)
    }
}

/// The GraphQL bodies a stub was sent, as JSON objects.
final class Bodies: Sendable {
    private let items = Mutex<[Data]>([])

    func add(_ body: Data) { items.withLock { $0.append(body) } }

    var all: [[String: Any]] {
        get throws {
            try items.withLock { $0 }.map { try #require(try JSONSerialization.jsonObject(with: $0) as? [String: Any]) }
        }
    }

    /// The one body sent.
    func only() throws -> [String: Any] {
        let all = try all
        try #require(all.count == 1)
        return all[0]
    }
}
