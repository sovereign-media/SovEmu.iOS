import CryptoKit
import SovEmuKit
import SwiftUI
import UIKit

/// Artwork from the server, kept in memory and on disk by its URL without its signature
/// (`assetCacheKey`): the server signs URLs afresh each hour, and the same picture must not be
/// fetched again with each new signature. File URLs carry their own signature, so no token goes
/// with them.
actor ArtCache {
    static let shared = ArtCache()

    private let memory = NSCache<NSString, UIImage>()
    private let folder: URL
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 30
        return URLSession(configuration: configuration)
    }()

    init() {
        memory.totalCostLimit = 96 * 1024 * 1024
        folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "art", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    /// The picture at `url`, from memory, the disk or the server; nil when it cannot be had.
    func image(_ url: URL) async -> UIImage? {
        let key = assetCacheKey(url.absoluteString)
        if let hit = memory.object(forKey: key as NSString) { return hit }
        if let running = inFlight[key] { return await running.value }
        let file = folder.appending(path: Self.name(key))
        let task = Task<UIImage?, Never> { [session] in
            if let data = try? Data(contentsOf: file), let image = UIImage(data: data) { return image.preparingForDisplay() ?? image }
            guard let (data, response) = try? await session.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200, let image = UIImage(data: data) else { return nil }
            try? data.write(to: file, options: .atomic)
            return image.preparingForDisplay() ?? image
        }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        if let image {
            let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
            memory.setObject(image, forKey: key as NSString, cost: cost)
        }
        return image
    }

    private static func name(_ key: String) -> String {
        SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// A picture from the server (a relative `/media/…` path the API handed out), filling its box;
/// nothing while there is none, or until it loads. `pixelated` scales without smoothing (a save's
/// screenshot is console pixels). `shape` is set to the picture's own width over height once it
/// loads (a binding, not a closure, so a trailing closure stays `onLoaded`). `onLoaded` says
/// whether it drew.
struct RemoteImage: View {
    @Environment(AppModel.self) private var model
    let path: String?
    var contentMode: ContentMode = .fill
    var pixelated = false
    var shape: Binding<Double?>? = nil
    var onLoaded: ((Bool) -> Void)?
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(pixelated ? .none : .high)
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .task(id: path) {
            guard let url = model.api?.media(path) else {
                image = nil
                onLoaded?(false)
                return
            }
            let loaded = await ArtCache.shared.image(url)
            withAnimation(.easeOut(duration: 0.2)) { image = loaded }
            if let loaded, loaded.size.height > 0 { shape?.wrappedValue = loaded.size.width / loaded.size.height }
            onLoaded?(loaded != nil)
        }
    }
}
