import Foundation
import Testing
@testable import SovEmuKit

/// The GraphQL requests the client sends and how it reads the answers (`schema.graphql` in
/// SovEmu.Server).
struct APITests {
    private let base = URL(string: "http://192.168.1.20:8080")!

    private func body(_ request: URLRequest) throws -> [String: Any] {
        let data = try #require(request.httpBody)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func decode<T: Decodable>(_ type: T.Type, _ field: String, _ json: String, status: Int = 200) throws -> T {
        try SovEmuAPI.decode(T.self, field: field, from: Data(json.utf8), status: status)
    }

    @Test func postsQueryAndVariablesToGraphql() throws {
        let request = try SovEmuAPI.request(
            baseURL: base, query: Documents.games, variables: ["system": .string("nes")])
        #expect(request.url?.absoluteString == "http://192.168.1.20:8080/graphql")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let json = try body(request)
        #expect(json["query"] as? String == Documents.games)
        #expect(json["variables"] as? [String: String] == ["system": "nes"])
        // The API authenticates with tokens, never cookies.
        #expect(!request.httpShouldHandleCookies)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func encodesIntAndBoolVariablesAsJsonNumbersAndBooleans() throws {
        let request = try SovEmuAPI.request(
            baseURL: base, query: Documents.saveState, variables: ["sessionId": .string("s1"), "slot": .int(3), "on": .bool(true)])
        let variables = try #require(try body(request)["variables"] as? [String: Any])
        #expect(variables["slot"] as? Int == 3)
        #expect(variables["on"] as? Bool == true)
        #expect(variables["sessionId"] as? String == "s1")
        // No variables still sends an object, never null.
        let bare = try body(SovEmuAPI.request(baseURL: base, query: Documents.systems, variables: [:]))
        #expect((bare["variables"] as? [String: Any])?.isEmpty == true)
    }

    @Test func documentsUseTheSchemasNames() {
        #expect(Documents.viewer.contains("viewer { setupRequired user { id username isAdmin role } }"))
        #expect(Documents.games.contains("system(id: $system) { games {"))
        #expect(Documents.startSession.contains("startSession(gameId: $gameId, startId: $startId)"))
        #expect(Documents.sessionOffer.contains("sessionOffer(id: $id, sdp: $sdp, client: $client)"))
        #expect(Documents.sessionOffer.contains("$client: String)"))
        #expect(Documents.loadState.contains("loadState(sessionId: $sessionId, slot: $slot)"))
        #expect(Documents.nameDevice == "mutation NameDevice($name: String!) { nameDevice(name: $name) }")
        for document in [Documents.viewer, Documents.systems, Documents.games, Documents.startSession] {
            #expect(!document.contains("_"), "camelCase, not snake_case: \(document)")
        }
    }

    @Test func theOfferNamesTheClient() throws {
        let variables = SovEmuAPI.offerVariables(sessionId: "s1", sdp: "v=0", client: "ios 0.1.0 (iPhone, iOS 26.0)")
        #expect(variables == ["id": .string("s1"), "sdp": .string("v=0"), "client": .string("ios 0.1.0 (iPhone, iOS 26.0)")])
        #expect(SovEmuAPI.offerVariables(sessionId: "s1", sdp: "v=0", client: nil)["client"] == .null)
    }

    @Test func decodesViewerAndSystems() throws {
        let status = try decode(AuthStatus.self, "viewer", """
            {"data":{"viewer":{"setupRequired":false,"user":{"id":1,"username":"ada","isAdmin":true,"role":"ADMIN"}}}}
            """)
        #expect(status.user == User(id: 1, username: "ada", isAdmin: true, role: .admin))
        let viewer = try decode(AuthStatus.self, "viewer", """
            {"data":{"viewer":{"setupRequired":false,"user":{"id":2,"username":"bo","isAdmin":false,"role":"VIEWER"}}}}
            """)
        #expect(viewer.user?.role == .viewer)
        let newer = try decode(User.self, "user", #"{"data":{"user":{"id":3,"username":"cy","isAdmin":false,"role":"GUEST"}}}"#)
        #expect(newer.role == .viewer, "an unknown role grants no more than viewing")
        #expect(try decode(AuthStatus.self, "viewer", #"{"data":{"viewer":{"setupRequired":true,"user":null}}}"#).user == nil)

        let systems = try decode([SystemSummary].self, "systems", """
            {"data":{"systems":[{"id":"nes","name":"Nintendo Entertainment System","short":"NES",
             "manufacturer":"Nintendo","year":1983,"color":"#c0392b","gameCount":2,"playable":true,
             "needsGpu":false,"rendering":null,"extra":1},
             {"id":"n64","name":"Nintendo 64","short":"N64","manufacturer":"Nintendo","year":1996,
             "color":"#2c3e50","gameCount":0,"playable":true,"needsGpu":true,"rendering":"SOFTWARE"}]}}
            """)
        #expect(systems[0].gameCount == 2)
        #expect(systems[0].rgb.0 > 0.75 && systems[0].rgb.2 < 0.25)
        #expect(systems[1].needsGpu && systems[1].rendering == "SOFTWARE")
    }

    @Test func decodesGamesSessionsAndConfig() throws {
        // `size` is a GraphQL Float, and may come with a fraction part.
        let games = try decode([String: [Game]]?.self, "system", """
            {"data":{"system":{"games":[{"id":7,"system":"nes","title":"Alter Ego","tags":["USA","Rev 1"],
             "size":40976.0,"lastPlayedAt":null,"playCount":0}]}}}
            """)
        let game = try #require(games?["games"]?.first)
        #expect(game.tags == ["USA", "Rev 1"])
        #expect(game.size == 40976)
        #expect(try decode([String: [Game]]?.self, "system", #"{"data":{"system":null}}"#) == nil)

        let session = try decode(SessionInfo.self, "startSession", """
            {"data":{"startSession":{"id":"abc","gameId":7,"system":"nes","title":"Alter Ego",
             "core":"FCEUmm","width":256,"height":240,"fps":60.0988,"connected":false}}}
            """)
        #expect(session.id == "abc" && session.gameId == 7 && !session.connected)
        #expect(session.discs == nil, "an older server says nothing of discs")
        let multi = try decode(SessionInfo.self, "startSession", """
            {"data":{"startSession":{"id":"x","gameId":8,"system":"psx","title":"Epic",
             "core":"PCSX-ReARMed","width":256,"height":240,"fps":60.0,"connected":false,"discs":2,"disc":1}}}
            """)
        #expect(multi.discs == 2 && multi.disc == 1)
        #expect(SessionInfo.fields.hasSuffix("discs disc"))
        #expect(try decode(String.self, "sessionOffer", #"{"data":{"sessionOffer":"v=0\r\n"}}"#) == "v=0\r\n")
        #expect(try decode(Bool.self, "stopSession", #"{"data":{"stopSession":true}}"#))

        // `iceServers` is a JSON scalar holding `RTCIceServer` objects.
        let config = try decode(ClientConfig.self, "clientConfig", """
            {"data":{"clientConfig":{"iceServers":[{"urls":"stun:a"},
             {"urls":["turn:b","turns:c"],"username":"u","credential":"p"}]}}}
            """)
        #expect(config.iceServers.map(\.urls) == [["stun:a"], ["turn:b", "turns:c"]])
    }

    @Test func sendsAndReadsControllerMappings() throws {
        #expect(Documents.controllerMappings.contains("query ControllerMappings($system: ID) { controllerMappings(system: $system) {"))
        #expect(Documents.controllerMappings.contains("{ controller system name bindings { input button } source }"))
        #expect(Documents.saveControllerMapping.contains("$system: ID, $name: String!, $bindings: [BindingInput!]!"))
        #expect(Documents.saveControllerMapping.contains(
            "saveControllerMapping(controller: $controller, system: $system, name: $name, bindings: $bindings)"))
        #expect(Documents.resetControllerMapping.contains("($controller: String!, $system: ID)"))
        #expect(Documents.resetControllerMapping.contains("resetControllerMapping(controller: $controller, system: $system)"))

        // Bindings go as a list of objects with the schema's field names.
        let variables = SovEmuAPI.mappingVariables(
            controller: "dualsense", system: "megadrive", name: "DualSense Wireless Controller",
            bindings: [ControllerBinding(input: "south", button: "A"), ControllerBinding(input: "east", button: "B")])
        let request = try SovEmuAPI.request(baseURL: base, query: Documents.saveControllerMapping, variables: variables)
        let sent = try #require(try body(request)["variables"] as? [String: Any])
        #expect(sent["controller"] as? String == "dualsense")
        #expect(sent["system"] as? String == "megadrive")
        #expect(sent["name"] as? String == "DualSense Wireless Controller")
        #expect(sent["bindings"] as? [[String: String]] == [["input": "south", "button": "A"], ["input": "east", "button": "B"]])

        let mappings = try decode([ControllerMapping].self, "controllerMappings", """
            {"data":{"controllerMappings":[{"controller":"keyboard","system":null,"name":"Keyboard",
             "bindings":[{"input":"KeyP","button":"START"}],"source":"USER"},
             {"controller":"xbox","system":"megadrive","name":"Xbox","bindings":[],"source":"ENVIRONMENT"},
             {"controller":"dualsense","name":"DualSense","bindings":[],"source":"SOMETHING_NEW"}]}}
            """)
        #expect(mappings[0] == ControllerMapping(
            controller: "keyboard", name: "Keyboard", bindings: [ControllerBinding(input: "KeyP", button: "START")], source: .user))
        #expect(mappings.map(\.source) == [.user, .environment, .admin])
        #expect(mappings.map(\.system) == [nil, "megadrive", nil], "a missing system is every system")
        #expect(!mappings[0].source.isDefault && mappings[1].source.isDefault)
        #expect(try decode(Bool.self, "resetControllerMapping", #"{"data":{"resetControllerMapping":false}}"#) == false)

        let invalid = #"{"data":null,"errors":[{"message":"a controller ID is up to 64 lowercase letters","extensions":{"code":"BAD_REQUEST"}}]}"#
        let error = try #require(throws: APIError.self) { try decode(ControllerMapping.self, "saveControllerMapping", invalid) }
        #expect(error.code == "BAD_REQUEST")
    }

    @Test func sendsSystemsAsStringsOrNull() throws {
        // Every system is an explicit null, for saving, resetting and listing alike.
        let every = SovEmuAPI.mappingVariables(controller: "xbox", system: nil, name: "", bindings: [])
        let request = try SovEmuAPI.request(baseURL: base, query: Documents.saveControllerMapping, variables: every)
        let sent = try #require(try body(request)["variables"] as? [String: Any])
        #expect(sent["system"] is NSNull)
        #expect((sent["bindings"] as? [Any])?.isEmpty == true)

        #expect(SovEmuAPI.resetVariables(controller: "xbox", system: "snes") == ["controller": .string("xbox"), "system": .string("snes")])
        #expect(SovEmuAPI.resetVariables(controller: "xbox", system: nil) == ["controller": .string("xbox"), "system": .null])
        let reset = try SovEmuAPI.request(
            baseURL: base, query: Documents.resetControllerMapping, variables: SovEmuAPI.resetVariables(controller: "xbox", system: nil))
        let resetBody = try #require(reset.httpBody)
        let raw = try #require(String(data: resetBody, encoding: .utf8))
        #expect(raw.contains(#""system":null"#))
        #expect(MappingScope.system("megadrive").systemArgument == "megadrive")
        #expect(MappingScope.everySystem.systemArgument == nil)
    }

    @Test func decodesASystemsSticks() throws {
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

    @Test func decodesSystemControlsAndLayouts() throws {
        #expect(Documents.controls.contains("system(id: $system) { controls { buttons { button label } sticks { stick label key }"))
        #expect(Documents.controls.contains("controllerLayouts { id name width height body { x y w h r tone } keys { key label x y w h r } }"))

        let info = try SovEmuAPI.decodeData(ControlsInfo.self, from: Data(Fixtures.megadriveControls.utf8), status: 200)
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
        #expect(!controls.layout.body.isEmpty)
        #expect(Set(controls.layout.keys.map(\.key)) == Set(controls.buttons.map(\.button)), "every button is drawn")

        #expect(info.controllerLayouts.map(\.id) == ["xbox", "playstation", "nintendo", "generic"])
        let ps = try #require(info.layout(for: .playstation))
        #expect(ps.keys.first { $0.key == "south" }?.label == "✕")
        #expect(Set(ps.keys.map(\.key)) == Set(PadInput.allCases.map(\.rawValue)))
        #expect(info.layout(for: .generic)?.id == "generic")
        let shape = try #require(ps.body.first)
        #expect(shape.tone == 0 && shape.r > 0)

        // An unknown system has no controls; the controllers' diagrams still come.
        let none = try SovEmuAPI.decodeData(
            ControlsInfo.self, from: Data(#"{"data":{"system":null,"controllerLayouts":[]}}"#.utf8), status: 200)
        #expect(none.controls == nil && none.layout(for: .xbox) == nil)
        let failed = #"{"data":null,"errors":[{"message":"sign in first","extensions":{"code":"UNAUTHENTICATED"}}]}"#
        let error = try #require(throws: APIError.self) { try SovEmuAPI.decodeData(ControlsInfo.self, from: Data(failed.utf8), status: 200) }
        #expect(error.isUnauthenticated)
    }

    @Test func cropsDiagramsToWhatIsDrawn() throws {
        let info = try SovEmuAPI.decodeData(ControlsInfo.self, from: Data(Fixtures.megadriveControls.utf8), status: 200)
        // The Mega Drive's body is (10, 28, 140, 52), its Mode key tops out at y 23.
        let md = try #require(info.controls?.layout).visibleBounds
        #expect(md.x == 7 && md.y == 20 && md.w == 146 && md.h == 63)
        // Never past the canvas, and the whole canvas when nothing is drawn.
        let edge = PadLayout(id: "t", name: "t", body: [PadShape(x: 1, y: 90, w: 159, h: 10, r: 0)], keys: [])
        #expect(edge.visibleBounds == (0, 87, 160, 13))
        #expect(PadLayout(id: "t", name: "t", body: [], keys: []).visibleBounds == (0, 0, 160, 100))
    }

    @Test func throwsTheFirstErrorWithItsCode() throws {
        let unauthenticated = """
            {"data":null,"errors":[{"message":"sign in first","locations":[{"line":1,"column":17}],
             "path":["systems"],"extensions":{"code":"UNAUTHENTICATED"}}]}
            """
        let error = try #require(throws: APIError.self) { try decode([SystemSummary].self, "systems", unauthenticated) }
        #expect(error.code == "UNAUTHENTICATED" && error.isUnauthenticated)
        #expect(error.localizedDescription == "sign in first")

        let wrong = #"{"data":null,"errors":[{"message":"wrong username or password","extensions":{"code":"UNAUTHENTICATED"}}]}"#
        #expect(throws: APIError.self) { try decode(AuthStatus.self, "viewer", wrong) }

        let missing = #"{"data":null,"errors":[{"message":"no such game","extensions":{"code":"NOT_FOUND"}}]}"#
        let notFound = try #require(throws: APIError.self) { try decode(SessionInfo.self, "startSession", missing) }
        #expect(notFound.code == "NOT_FOUND" && !notFound.isUnauthenticated)

        // An error without extensions still carries its message.
        let plain = try #require(throws: APIError.self) {
            try decode(Bool.self, "stopSession", #"{"data":null,"errors":[{"message":"boom"}]}"#)
        }
        #expect(plain.code == nil && plain.message == "boom")
    }

    @Test func reportsHttpFailuresAndUnreadableAnswers() throws {
        let gateway = try #require(throws: APIError.self) { try decode(Bool.self, "stopSession", "<html>", status: 502) }
        #expect(gateway.status == 502 && gateway.code == nil)
        let odd = try #require(throws: APIError.self) { try decode(Bool.self, "stopSession", #"{"data":{"stopSession":"yes"}}"#) }
        #expect(odd.status == 200)
        #expect(APIError(status: 401, message: "").isUnauthenticated)
    }
}
