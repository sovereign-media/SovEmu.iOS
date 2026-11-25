import SovEmuKit
import SwiftUI

/// SovEmu's own age-rating badge, as the web client's `assets/esrb/*.svg`: a 60×80 white tile
/// with a near-black border, the rating's code in heavy type, and its ages on a near-black strip
/// along the bottom. Not the ESRB's icon. Drawn in the SVG's units, scaled to `height`.
struct EsrbBadge: View {
    let rating: EsrbRating
    var height: CGFloat = 56

    private static let ink = Color(red: 0x11 / 255, green: 0x11 / 255, blue: 0x11 / 255)

    var body: some View {
        let s = height / 80
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6 * s).fill(.white)
                .frame(width: 56 * s, height: 76 * s).offset(x: 2 * s, y: 2 * s)
            UnevenRoundedRectangle(bottomLeadingRadius: 6 * s, bottomTrailingRadius: 6 * s).fill(Self.ink)
                .frame(width: 56 * s, height: 18 * s).offset(x: 2 * s, y: 60 * s)
            RoundedRectangle(cornerRadius: 6 * s).strokeBorder(Self.ink, lineWidth: 4 * s)
                .frame(width: 60 * s, height: 80 * s)
            code(s).position(x: 30 * s, y: 37 * s)
            Text(rating.ages)
                .font(.system(size: 8.5 * s, weight: .heavy))
                .foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.5)
                .frame(width: 50 * s)
                .position(x: 30 * s, y: 69 * s)
        }
        .frame(width: 60 * s, height: 80 * s)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rating.accessibilityLabel)
    }

    /// The code at the SVG's sizes: one letter large, two smaller, E10+ with a raised plus.
    @ViewBuilder private func code(_ s: CGFloat) -> some View {
        switch rating {
        case .everyone10Plus:
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("E10").font(.system(size: 21 * s, weight: .black))
                Text("+").font(.system(size: 14 * s, weight: .black)).baselineOffset(5 * s)
            }
            .foregroundStyle(Self.ink)
        default:
            Text(rating.code)
                .font(.system(size: (rating.code.count == 1 ? 44 : 30) * s, weight: .black))
                .foregroundStyle(Self.ink)
        }
    }
}

#Preview {
    HStack(spacing: 12) {
        ForEach(EsrbRating.allCases, id: \.self) { EsrbBadge(rating: $0) }
    }
    .padding()
    .background(Color.gray)
}
