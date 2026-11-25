import SovEmuKit
import SwiftUI
import UIKit

/// An ESRB rating's badge: the ESRB's own icon (the 2013 set, from Wikimedia Commons), a WebP
/// image the app ships (`Esrb/esrb_<rating>.webp`, the same files the web client ships, rendered
/// by its `npm run esrb-badges`), shown `height` tall. Bundled rather than loaded
/// from the server, whose signed per-user URLs cache poorly. iOS decodes WebP since 14.
struct EsrbBadge: View {
    let rating: EsrbRating
    var height: CGFloat = 56

    var body: some View {
        if let image = Self.image(rating) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(height: height)
                .accessibilityLabel(rating.accessibilityLabel)
        }
    }

    /// The badge's image from the app's bundle, read once per rating.
    @MainActor private static var cache: [EsrbRating: UIImage] = [:]

    @MainActor private static func image(_ rating: EsrbRating) -> UIImage? {
        if let image = cache[rating] { return image }
        guard let path = Bundle.main.path(forResource: rating.badgeName, ofType: "webp"),
              let image = UIImage(contentsOfFile: path)
        else { return nil }
        cache[rating] = image
        return image
    }
}

#Preview {
    HStack {
        ForEach(EsrbRating.allCases, id: \.self) { EsrbBadge(rating: $0) }
    }
    .padding()
    .background(.black)
}
