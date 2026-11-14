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
            baseURL: base, query: Documents.login, variables: ["username": .string("ada"), "password": .string("pw")])
        #expect(request.url?.absoluteString == "http://192.168.1.20:8080/graphql")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let json = try body(request)
        #expect(json["query"] as? String == Documents.login)
        #expect(json["variables"] as? [String: String] == ["username": "ada", "password": "pw"])
    }

    @Test func encodesIntAndBoolVariablesAsJsonNumbersAndBooleans() throws {
        let request = try SovEmuAPI.request(
            baseURL: base, query: Documents.saveState, variables: ["sessionId": .string("s1"), "slot": .int(3), "on": .bool(true)])
        let variables = try #require(try body(request)["variables"] as? [String: Any])
        #expect(variables["slot"] as? Int == 3)
        #expect(variables["on"] as? Bool == true)
        #expect(variables["sessionId"] as? String == "s1")
        // No variables still sends an object, never null.
        let bare = try body(SovEmuAPI.request(baseURL: base, query: Documents.logout, variables: [:]))
        #expect((bare["variables"] as? [String: Any])?.isEmpty == true)
    }

    @Test func documentsUseTheSchemasNames() {
        #expect(Documents.viewer.contains("viewer { setupRequired user { id username isAdmin } }"))
        #expect(Documents.games.contains("system(id: $system) { games {"))
        #expect(Documents.startSession.contains("startSession(gameId: $gameId)"))
        #expect(Documents.sessionOffer.contains("sessionOffer(id: $id, sdp: $sdp)"))
        #expect(Documents.loadState.contains("loadState(sessionId: $sessionId, slot: $slot)"))
        for document in [Documents.viewer, Documents.login, Documents.systems, Documents.games, Documents.startSession] {
            #expect(!document.contains("_"), "camelCase, not snake_case: \(document)")
        }
    }

    @Test func decodesViewerAndSystems() throws {
        let status = try decode(AuthStatus.self, "viewer", """
            {"data":{"viewer":{"setupRequired":false,"user":{"id":1,"username":"ada","isAdmin":true}}}}
            """)
        #expect(status.user == User(id: 1, username: "ada", isAdmin: true))
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
        #expect(try decode(String.self, "sessionOffer", #"{"data":{"sessionOffer":"v=0\r\n"}}"#) == "v=0\r\n")
        #expect(try decode(Bool.self, "logout", #"{"data":{"logout":true}}"#))

        // `iceServers` is a JSON scalar holding `RTCIceServer` objects.
        let config = try decode(ClientConfig.self, "clientConfig", """
            {"data":{"clientConfig":{"iceServers":[{"urls":"stun:a"},
             {"urls":["turn:b","turns:c"],"username":"u","credential":"p"}]}}}
            """)
        #expect(config.iceServers.map(\.urls) == [["stun:a"], ["turn:b", "turns:c"]])
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
        #expect(throws: APIError.self) { try decode(User.self, "login", wrong) }

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
        let gateway = try #require(throws: APIError.self) { try decode(Bool.self, "logout", "<html>", status: 502) }
        #expect(gateway.status == 502 && gateway.code == nil)
        let odd = try #require(throws: APIError.self) { try decode(Bool.self, "logout", #"{"data":{"logout":"yes"}}"#) }
        #expect(odd.status == 200)
        #expect(APIError(status: 401, message: "").isUnauthenticated)
    }
}
