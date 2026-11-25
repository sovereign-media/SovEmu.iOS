import SovEmuKit
import SwiftUI

/// An ESRB rating's icon from the server (`Game.esrbBadgeUrl`: the ESRB's own, from the server's
/// built-in decoration set, which an admin may replace), loaded and cached as artwork is
/// (`RemoteImage`), shown `height` tall at the icons' 2:3, named for VoiceOver.
struct EsrbBadge: View {
    let rating: EsrbRating
    let url: String
    var height: CGFloat = 56

    var body: some View {
        RemoteImage(path: url, contentMode: .fit)
            .frame(width: height * 2 / 3, height: height)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isImage)
            .accessibilityLabel(rating.accessibilityLabel)
    }
}
