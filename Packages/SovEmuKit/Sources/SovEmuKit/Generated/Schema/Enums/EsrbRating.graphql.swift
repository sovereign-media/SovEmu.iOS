// @generated
// This file was automatically generated and should not be edited.

@_spi(Internal) import ApolloAPI

extension SovEmuGraphQL {
  /// The ESRB's age ratings.
  nonisolated enum EsrbRating: String, EnumType {
    /// EC: Early Childhood (until 2018).
    case earlyChildhood = "EARLY_CHILDHOOD"
    /// E: Everyone (K-A, Kids to Adults, until 1998).
    case everyone = "EVERYONE"
    /// E10+: Everyone 10+.
    case everyone10Plus = "EVERYONE_10_PLUS"
    /// T: Teen.
    case teen = "TEEN"
    /// M: Mature 17+.
    case mature = "MATURE"
    /// AO: Adults Only 18+.
    case adultsOnly = "ADULTS_ONLY"
    /// RP: Rating Pending.
    case ratingPending = "RATING_PENDING"
  }

}