import Foundation
import Combine

/// Persists favorite display modes in UserDefaults.
@MainActor
final class FavoritesStore: ObservableObject {
    @Published private(set) var favorites: [FavoritePreset] = []

    private let defaultsKey = "flexdisplay.favorites.v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        load()
    }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else {
            favorites = []
            return
        }
        do {
            favorites = try decoder.decode([FavoritePreset].self, from: data)
        } catch {
            favorites = []
        }
    }

    func save() {
        do {
            let data = try encoder.encode(favorites)
            UserDefaults.standard.set(data, forKey: defaultsKey)
        } catch {
            // Keep in-memory state; next save may succeed.
        }
    }

    @discardableResult
    func add(from display: DisplayInfo, mode: DisplayModeInfo) -> FavoritePreset {
        let preset = FavoritePreset(
            id: UUID(),
            displayUUID: display.uuid,
            displayName: display.name,
            width: mode.width,
            height: mode.height,
            refreshRate: mode.refreshRate,
            isHiDPI: mode.isHiDPI,
            createdAt: Date()
        )
        // Avoid exact duplicates for same display + geometry
        if let existing = favorites.first(where: {
            $0.displayUUID == preset.displayUUID && $0.matches(mode)
        }) {
            return existing
        }
        favorites.insert(preset, at: 0)
        save()
        return preset
    }

    func remove(_ preset: FavoritePreset) {
        favorites.removeAll { $0.id == preset.id }
        save()
    }

    func remove(id: UUID) {
        favorites.removeAll { $0.id == id }
        save()
    }
}
