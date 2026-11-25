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

    @Test func everyRatingHasItsOwnBadgeImage() {
        let names = EsrbRating.allCases.map(\.badgeName)
        #expect(Set(names).count == EsrbRating.allCases.count)
        #expect(EsrbRating.everyone10Plus.badgeName == "esrb_e10")
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

    private func decode(_ json: String) throws -> Game {
        try JSONDecoder().decode(Game.self, from: Data(json.utf8))
    }

    @Test func aGameDecodesItsRatingAndLists() throws {
        let game = try decode(##"""
            {"id": 7, "system": "nes", "title": "Castlevania", "rating": 0.8, "esrb": "EVERYONE_10_PLUS",
             "modes": ["Single player"], "series": ["Castlevania"], "themes": ["Horror", "Fantasy"],
             "genres": ["Platform", "Action"], "genre": "Platform, Action"}
            """##)
        #expect(game.esrb == .everyone10Plus)
        #expect(game.rating == 0.8)
        #expect(game.modes == ["Single player"])
        #expect(game.series == ["Castlevania"])
        #expect(game.themes == ["Horror", "Fantasy"])
        #expect(game.genres == ["Platform", "Action"])
    }

    @Test func anOlderServersGameDecodesWithoutThem() throws {
        let game = try decode(##"{"id": 7, "system": "nes", "title": "Castlevania"}"##)
        #expect(game.esrb == nil)
        #expect(game.modes.isEmpty && game.series.isEmpty && game.themes.isEmpty && game.genres.isEmpty)
        #expect(try decode(##"{"id": 7, "system": "nes", "title": "C", "esrb": null}"##).esrb == nil)
    }

    @Test func anUnknownRatingIsNoRating() throws {
        let game = try decode(##"{"id": 7, "system": "nes", "title": "Castlevania", "esrb": "PEGI_99", "modes": ["Co-op"]}"##)
        #expect(game.esrb == nil)
        #expect(game.modes == ["Co-op"])
    }

    @Test func theGameFieldsAskForTheNewFields() {
        #expect(Game.fields.contains("rating esrb modes series themes genres"))
    }

    @Test func homeAsksForTopRated() throws {
        #expect(Documents.home.contains("topRated {"))
        let rows = try JSONDecoder().decode(HomeRows.self, from: Data(##"""
            {"featured": [], "recent": [], "added": [], "favourites": [],
             "topRated": [{"id": 1, "system": "snes", "title": "Chrono Trigger", "rating": 0.95}]}
            """##.utf8))
        #expect(rows.topRated.map(\.id) == [1])
        let older = try JSONDecoder().decode(HomeRows.self, from: Data(##"{"featured": [], "recent": [], "added": [], "favourites": []}"##.utf8))
        #expect(older.topRated.isEmpty)
    }
}
