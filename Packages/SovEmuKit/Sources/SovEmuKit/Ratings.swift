import Foundation

// MARK: - Age ratings and the rating's stars

/// The ESRB's age ratings (`EsrbRating`). The app shows each as the ESRB's own icon (the 2013
/// set, from Wikimedia Commons): a WebP image it ships, the same file the web client ships,
/// rendered by its `npm run esrb-badges`.
public enum EsrbRating: String, Codable, Sendable, Hashable, CaseIterable {
    case earlyChildhood = "EARLY_CHILDHOOD"
    case everyone = "EVERYONE"
    case everyone10Plus = "EVERYONE_10_PLUS"
    case teen = "TEEN"
    case mature = "MATURE"
    case adultsOnly = "ADULTS_ONLY"
    case ratingPending = "RATING_PENDING"

    /// The code on the badge: "EC", "E", "E10+", "T", "M", "AO", "RP".
    public var code: String {
        switch self {
        case .earlyChildhood: "EC"
        case .everyone: "E"
        case .everyone10Plus: "E10+"
        case .teen: "T"
        case .mature: "M"
        case .adultsOnly: "AO"
        case .ratingPending: "RP"
        }
    }

    /// The rating's name, as read out: "Everyone 10+".
    public var name: String {
        switch self {
        case .earlyChildhood: "Early Childhood"
        case .everyone: "Everyone"
        case .everyone10Plus: "Everyone 10+"
        case .teen: "Teen"
        case .mature: "Mature 17+"
        case .adultsOnly: "Adults Only 18+"
        case .ratingPending: "Rating Pending"
        }
    }

    /// The badge's bottom strip, in caps: "AGES 10+".
    public var ages: String {
        switch self {
        case .earlyChildhood: "AGES 3+"
        case .everyone: "EVERYONE"
        case .everyone10Plus: "AGES 10+"
        case .teen: "TEEN"
        case .mature: "MATURE 17+"
        case .adultsOnly: "ADULTS 18+"
        case .ratingPending: "PENDING"
        }
    }

    /// The badge image's name in the app's bundle (`esrb_e10`, with the `webp` extension).
    public var badgeName: String {
        switch self {
        case .earlyChildhood: "esrb_ec"
        case .everyone: "esrb_e"
        case .everyone10Plus: "esrb_e10"
        case .teen: "esrb_t"
        case .mature: "esrb_m"
        case .adultsOnly: "esrb_ao"
        case .ratingPending: "esrb_rp"
        }
    }

    /// The badge's accessibility label: "ESRB: Everyone 10+ (E10+)".
    public var accessibilityLabel: String { "ESRB: \(name) (\(code))" }
}

/// A rating (0 to 1) as stars out of 5, to the nearest half: 0.8 is 4, 0.72 is 3.5.
public func ratingStars(_ rating: Double) -> Double {
    (min(max(rating, 0), 1) * 10).rounded() / 2
}

/// A rating as the details say it: "4 out of 5", "3.5 out of 5".
public func formatRating(_ rating: Double?) -> String? {
    guard let rating else { return nil }
    let stars = ratingStars(rating)
    let number = stars == stars.rounded() ? String(Int(stars)) : String(stars)
    return "\(number) out of 5"
}
