import Foundation
import Testing
@testable import SovEmuKit

/// The age ratings' table, the stars, the new game fields and the Home query's Top rated row.
struct RatingsTests {
    @Test func everyRatingHasItsCodeNameAndAges() {
        let table = EsrbRating.allCases.map { [$0.rawValue, $0.code, $0.name, $0.ages] }
        #expect(table == [
            ["EARLY_CHILDHOOD", "EC", "Early Childhood", "AGES 3+"],
            ["EVERYONE", "E", "Everyone", "EVERYONE"],
            ["EVERYONE_10_PLUS", "E10+", "Everyone 10+", "AGES 10+"],
            ["TEEN", "T", "Teen", "TEEN"],
            ["MATURE", "M", "Mature 17+", "MATURE 17+"],
            ["ADULTS_ONLY", "AO", "Adults Only 18+", "ADULTS 18+"],
            ["RATING_PENDING", "RP", "Rating Pending", "PENDING"],
        ])
        #expect(EsrbRating.everyone10Plus.accessibilityLabel == "ESRB: Everyone 10+ (E10+)")
    }

    @Test func ratingsRoundToHalfStars() {
        #expect(ratingStars(0.8) == 4)
        #expect(ratingStars(0.72) == 3.5)
        #expect(ratingStars(0.74) == 3.5)
        #expect(ratingStars(0.76) == 4)
        #expect(ratingStars(0) == 0)
        #expect(ratingStars(1) == 5)
        #expect(ratingStars(1.4) == 5)
        #expect(formatRating(0.8) == "4 out of 5")
        #expect(formatRating(0.72) == "3.5 out of 5")
        #expect(formatRating(1) == "5 out of 5")
        #expect(formatRating(0.05) == "0.5 out of 5")
        #expect(formatRating(nil) == nil)
    }

    /// A game as the server sends it, read through the API.
    private func game(_ extra: String) async throws -> Game {
        let stub = Stub { _, _ in (200, #"{"data":{"search":["# + APITests.game(id: 7, extra: extra) + "]}}") }
        return try #require(try await SovEmuAPI(baseURL: stub.base, session: stub.session).search("c").first)
    }

    @Test func aGameReadsItsRatingAndLists() async throws {
        let game = try await game(##""rating":0.8,"esrb":"EVERYONE_10_PLUS","esrbBadgeUrl":"/media/decorations/sovemu/ratings/esrb/e10.png?Sov-UserId=1","modes":["Single player"],"series":["Castlevania"],"themes":["Horror"],"genres":["Platform"],"genre":"Platform""##)
        #expect(game.esrb == .everyone10Plus)
        #expect(game.esrbBadgeUrl == "/media/decorations/sovemu/ratings/esrb/e10.png?Sov-UserId=1")
        #expect(game.rating == 0.8)
        #expect(game.modes == ["Single player"] && game.series == ["Castlevania"])
        #expect(game.themes == ["Horror"] && game.genres == ["Platform"])
    }

    @Test func anUnknownRatingIsNoRating() async throws {
        #expect(try await game(##""esrb":"PEGI_99""##).esrb == nil)
        #expect(try await game(##""esrb":null"##).esrb == nil)
    }
}
