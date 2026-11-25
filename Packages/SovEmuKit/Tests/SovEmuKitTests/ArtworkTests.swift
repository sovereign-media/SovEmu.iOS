import Foundation
import Testing
@testable import SovEmuKit

/// The same cases as SovEmu.Android's ArtworkTest and SovEmu.Web's boxArt tests.
struct ArtworkTests {
    @Test func artOfNearlyTheCardsShapeFillsIt() {
        #expect(artFills(1.4, 1.4))
        #expect(artFills(1.33, 1.4), "a US SNES box in a SNES card")
        #expect(artFills(0.7, 0.72))
    }

    @Test func artOfAnotherShapeIsShownWhole() {
        #expect(!artFills(0.72, 1.4), "a Super Famicom box in a SNES card")
        #expect(!artFills(1.4, 0.72))
        #expect(!artFills(4.0 / 3.0, 1.0), "a screenshot in a jewel-case card")
    }

    @Test func unknownShapesFill() {
        #expect(artFills(0, 1.4))
        #expect(artFills(.nan, 1.4))
    }

    @Test func systemsSayTheirBoxShape() async throws {
        let stub = Stub { _, _ in
            (200, ##"{"data":{"systems":[{"id":"snes","name":"Super Nintendo","short":"SNES","manufacturer":"Nintendo","year":1990,"color":"#000","gameCount":1,"playable":true,"needsGpu":false,"rendering":null,"biosMissing":false,"boxAspect":1.4}]}}"##)
        }
        let snes = try #require(try await SovEmuAPI(baseURL: stub.base, session: stub.session).systems().first)
        #expect(snes.boxAspect == 1.4)
        #expect(SystemSummary(id: "x", name: "X", short: "X").boxAspect == defaultBoxAspect, "the portrait card by default")
    }
}
