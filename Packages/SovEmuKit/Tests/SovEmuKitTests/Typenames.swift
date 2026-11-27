import Foundation

/// What the server adds to every GraphQL answer the app's Apollo documents ask for: each object's
/// `__typename` (Apollo selects it on every object, and reads it back). The stub server
/// (`StubProtocol`) puts it into the answers tests write, so they can be written as the data alone.
enum Typenames {
    /// The schema type of the objects under each field name the documents use.
    static let byField: [String: String] = [
        "bootstrapConfig": "BootstrapConfig", "viewer": "Viewer", "user": "User", "clientConfig": "ClientConfig",
        "systems": "System", "system": "System", "games": "Game", "search": "Game", "game": "Game",
        "featured": "Game", "recent": "Game", "added": "Game", "topRated": "Game", "favourites": "Game",
        "home": "Home", "collections": "Collection", "createCollection": "Collection", "autoSave": "SaveSlot",
        "saves": "SaveSlot", "patches": "Patch", "decoration": "Decoration", "cheats": "Cheat", "addCheat": "Cheat",
        "setCheatEnabled": "Cheat", "startSession": "GameSession", "startProgress": "StartStatus",
        "controllerMappings": "ControllerMapping", "saveControllerMapping": "ControllerMapping", "bindings": "Binding",
        "controls": "SystemControls", "buttons": "SystemButton", "sticks": "SystemStick", "layout": "PadLayout",
        "controllerLayouts": "PadLayout", "body": "Shape", "keys": "PadKey", "background": "Background",
    ]

    /// `json` with `__typename` on every object under a known field of `data`; anything else
    /// (an error, a non-JSON body) unchanged.
    static func add(_ json: String) -> String {
        guard var answer = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any],
              let data = answer["data"] as? [String: Any] else { return json }
        answer["data"] = data.reduce(into: [String: Any]()) { $0[$1.key] = tag($1.value, field: $1.key) }
        guard let out = try? JSONSerialization.data(withJSONObject: answer) else { return json }
        return String(decoding: out, as: UTF8.self)
    }

    private static func tag(_ value: Any, field: String) -> Any {
        // A JSON scalar's contents (`iceServers`) are not objects of the schema.
        guard let type = byField[field] else { return value }
        if let list = value as? [Any] { return list.map { tag($0, field: field) } }
        guard var object = value as? [String: Any] else { return value }
        for (key, child) in object { object[key] = tag(child, field: key) }
        object["__typename"] = type
        return object
    }
}
