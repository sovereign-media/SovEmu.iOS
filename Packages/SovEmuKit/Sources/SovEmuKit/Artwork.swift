import Foundation

/// A card's shape when its system gives none: the old portrait card.
public let defaultBoxAspect = 3.0 / 4.0

/// How far (as a ratio) art's shape may be from its card's and still fill it, as the web's.
private let close = 1.15

/// Whether box art fills its card (cropping a little) rather than showing whole inside it. A
/// system's cards take the shape of its boxes (`SystemSummary.boxAspect`: SNES landscape, NES
/// portrait); art close to that shape fills the card, art of another shape (a Super Famicom box in
/// a SNES grid, a screenshot) is shown whole. Unknown shapes fill. The same rule as SovEmu.Web's
/// `artFit` and SovEmu.Android's `artFills`.
public func artFills(_ imageAspect: Double, _ cardAspect: Double) -> Bool {
    guard imageAspect > 0, cardAspect > 0, imageAspect.isFinite else { return true }
    return abs(log(imageAspect / cardAspect)) <= log(close)
}
