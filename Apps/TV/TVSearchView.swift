// Search on the TV, as SovEmu.Android's TV app (`feature-tv`'s `ui/Search.kt`): the page's
// title, a field (Select opens tvOS's keyboard), the line saying how many, then the matching
// games as covers; one opens its system with its panel open. The asking is `SearchView`'s,
// shared with the iPhone and iPad.
import SovEmuKit
import SwiftUI


struct TVSearchView: View {
    @Environment(AppModel.self) private var model
    @Environment(Library.self) private var library
    /// The Search tab's way back: a result opens its system's page with its panel open.
    @Binding var path: [Route]
    /// Kept with the screen, so Back from a system shows the same results.
    @State private var query = ""
    @State private var results: Load<[Game]>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16 * launchDp) {
                Text("Search").font(.system(size: 30 * launchDp, weight: .bold)).foregroundStyle(.white)
                LaunchInput(placeholder: "Search every system: titles, makers, genres", text: $query, keyboard: .default)
                    .frame(maxWidth: 640 * launchDp)
                    .onChange(of: query) { _, typed in if typed.count > 100 { query = String(typed.prefix(100)) } }
                Text(SearchView.summary(results) ?? " ")
                    .font(.system(size: 14 * launchDp))
                    .foregroundStyle(SearchView.isFailure(results) ? Sov.red300 : Sov.slate400)
            }
            .padding(.top, 40 * launchDp).padding(.bottom, 8 * launchDp)
            .frame(maxWidth: .infinity, alignment: .leading)
            .focusSection()
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 160 * launchDp), spacing: 16 * launchDp, alignment: .top)],
                alignment: .leading, spacing: 24 * launchDp
            ) {
                // The system page's covers, as Android TV's search shows them.
                ForEach(results?.value ?? []) { game in
                    if let system = library.system(game.system) {
                        TVCoverCard(game: game, system: system, isOpen: false) {
                            path.append(.system(system, open: game.id))
                        }
                    }
                }
            }
            .focusSection()
            .padding(.bottom, 112 * launchDp)
        }
        .contentMargins(.horizontal, 32 * launchDp, for: .scrollContent)
        .scrollClipDisabled()
        // No fill of its own: the dock's frame draws the surface and the admin's background
        // behind every page, as Android TV's `NavFrame`.
        .toolbar(.hidden, for: .navigationBar)
        .task(id: query) { results = await SearchView.search(query, api: model.api) ?? results }
    }
}
