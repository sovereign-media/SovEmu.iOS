// The Apple TV's search and filters, as SovEmu.Android's `FilterDrawer` (`:common:feature`
// SystemParts.kt, with the fields of `:common:designsystem` FilterFields.kt) on its TV app: a
// drawer from the right. It offers the filters SovEmuKit's `GameFilters` has (played, favourites,
// two players or more, genres); the iPhone's are Apps/Shared/SystemView.swift's `FilterSheet`.
import SovEmuKit
import SwiftUI


/// Search, then dropdowns with one choice (played, favourites, players) and with any number of
/// values (genres), each listing only what these games have. Menu or Play/Pause closes it; the
/// remote cannot leave it for the grid behind.
struct TVFilterDrawer: View {
    let index: GameIndex
    @Binding var query: String
    @Binding var filters: GameFilters
    let onClose: () -> Void

    private enum Field: Hashable { case played, favourites, players, genres, search, clear }
    @State private var menu: Field?
    @FocusState private var focus: Field?

    /// The most values a list filter's menu offers: past that it is easier to search.
    private static let maxValues = 60

    var body: some View {
        let n = filters.count + (query.trimmingCharacters(in: .whitespaces).isEmpty ? 0 : 1)
        let genres = Array(index.genreCounts.prefix(Self.maxValues))
        VStack(alignment: .leading, spacing: 0) {
            TVDrawerHeader(symbol: "slider.horizontal.3", title: "Filters", count: n)
            ScrollView {
                VStack(alignment: .leading, spacing: 24 * dp) {
                    TVTextBox(label: "Search titles, makers, genres", text: $query)
                        .focused($focus, equals: .search)
                        .disabled(menu != nil)
                    HStack(alignment: .top, spacing: 12 * dp) {
                        choice(.played, "Played", [
                            TVOption(value: PlayedFilter?.none, label: "Any"),
                            TVOption(value: PlayedFilter.played, label: "Played before"),
                            TVOption(value: PlayedFilter.unplayed, label: "Not played yet"),
                        ], selected: filters.played) { filters.played = $0 }
                        choice(.favourites, "Favourites", [
                            TVOption(value: false, label: "Any"),
                            TVOption(value: true, label: "Favourites only"),
                        ], selected: filters.favourites) { filters.favourites = $0 }
                    }
                    .zIndex(menu == .played || menu == .favourites ? 1 : 0)
                    if index.knowsPlayers {
                        HStack(alignment: .top, spacing: 12 * dp) {
                            choice(.players, "Players", [
                                TVOption(value: false, label: "Any"),
                                TVOption(value: true, label: "2 or more"),
                            ], selected: filters.multiplayer) { filters.multiplayer = $0 }
                            Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                        }
                        .zIndex(menu == .players ? 1 : 0)
                    }
                    if !genres.isEmpty {
                        genreField(genres).zIndex(menu == .genres ? 1 : 0)
                    }
                    if !index.knowsPlayers && genres.isEmpty {
                        Text("Player and genre filters appear once game information has been fetched for these games.")
                            .font(.system(size: 14 * dp)).foregroundStyle(Sov.slate500)
                    }
                }
                .padding(20 * dp)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollClipDisabled()
            if n > 0 {
                Rectangle().fill(.white.opacity(0.1)).frame(height: 1 * dp)
                Button {
                    filters = GameFilters()
                    query = ""
                    focus = .played
                } label: {
                    HStack(spacing: 6 * dp) {
                        Image(systemName: "xmark").font(.system(size: 14 * dp))
                        Text("Clear search and filters").font(.system(size: 14 * dp))
                    }
                    .foregroundStyle(Sov.slate400)
                }
                .buttonStyle(TVChipStyleQuiet())
                .focused($focus, equals: .clear)
                .disabled(menu != nil)
                .padding(20 * dp)
            }
        }
        .tvDrawerChrome(onClose: { if menu == nil { onClose() } })
        .onPlayPauseCommand { if menu == nil { onClose() } }
        // The first choice takes the focus: the remote passes over the search box until select.
        .onAppear { DispatchQueue.main.async { focus = .played } }
    }

    private func choice<V: Hashable>(_ field: Field, _ label: String, _ options: [TVOption<V>], selected: V,
                                     onSelect: @escaping (V) -> Void) -> some View {
        TVFieldBox(label: label, summary: options.first { $0.value == selected }?.label ?? options[0].label) { menu = field }
            .focused($focus, equals: field)
            .disabled(menu != nil)
            .dropdownBelow {
                if menu == field {
                    TVDropdown(options: options, isOn: { $0 == selected }, minWidth: 170 * dp,
                               onPick: { value in
                                   onSelect(value)
                                   close(field)
                               },
                               onClose: { close(field) })
                }
            }
            .frame(maxWidth: .infinity)
    }

    private func genreField(_ genres: [(genre: String, count: Int)]) -> some View {
        let selected = filters.genres
        let summary = switch selected.count {
        case 0: "Any"
        case 1: selected.first ?? "1 selected"
        default: "\(selected.count) selected"
        }
        return TVFieldBox(label: "Genre", summary: summary) { menu = .genres }
            .focused($focus, equals: .genres)
            .disabled(menu != nil)
            .dropdownBelow {
                if menu == .genres {
                    // Stays open while genres are ticked.
                    TVDropdown(options: genres.map { TVOption(value: $0.genre, label: $0.genre, count: $0.count) },
                               isOn: { selected.contains($0) }, minWidth: 344 * dp,
                               onClear: selected.isEmpty ? nil : {
                                   filters.genres = []
                                   close(.genres)
                               },
                               onPick: { genre in
                                   if filters.genres.contains(genre) { filters.genres.remove(genre) } else { filters.genres.insert(genre) }
                               },
                               onClose: { close(.genres) })
                }
            }
    }

    private func close(_ field: Field) {
        menu = nil
        DispatchQueue.main.async { focus = field }
    }
}

/// The drawer's "Clear" link: quiet text, a faint pill behind it when focused.
private struct TVChipStyleQuiet: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Body(label: configuration.label) }

    private struct Body<Label: View>: View {
        let label: Label
        @Environment(\.isFocused) private var focused

        var body: some View {
            label
                .padding(.horizontal, 8 * dp).padding(.vertical, 4 * dp)
                .background(focused ? Color.white.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6 * dp))
                .overlay { if focused { RoundedRectangle(cornerRadius: 6 * dp).strokeBorder(.white.opacity(0.6), lineWidth: 2 * dp) } }
        }
    }
}
