import Foundation
import CoreGraphics
import AppKit
import Combine

/// Enumerates displays, switches modes, and applies software (gamma) brightness.
@MainActor
final class DisplayService: ObservableObject {
    @Published private(set) var displays: [DisplayInfo] = []
    @Published var lastError: String?
    @Published var statusMessage: String?

    /// Per-display software brightness 0...1. Missing key = system default.
    private var brightnessByUUID: [String: Double] = [:]
    private let brightnessDefaultsKey = "flexdisplay.brightness.v1"

    /// Re-entrancy guard for configuration transactions.
    private var isConfiguring = false

    init() {
        loadBrightnessMap()
        refresh()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    // MARK: - Enumeration

    func refresh() {
        do {
            displays = try Self.enumerateDisplays(brightnessByUUID: brightnessByUUID)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            displays = []
        }
    }

    private static func enumerateDisplays(brightnessByUUID: [String: Double]) throws -> [DisplayInfo] {
        var displayCount: UInt32 = 0
        var err = CGGetActiveDisplayList(0, nil, &displayCount)
        guard err == .success, displayCount > 0 else {
            throw DisplayError.noDisplays
        }

        var ids = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        err = CGGetActiveDisplayList(displayCount, &ids, &displayCount)
        guard err == .success else {
            throw DisplayError.noDisplays
        }

        let mainID = CGMainDisplayID()
        let screens = NSScreen.screens

        return ids.prefix(Int(displayCount)).compactMap { did -> DisplayInfo? in
            let uuid = uuidString(for: did)
            let name = localizedName(for: did, screens: screens)
            let isBuiltIn = CGDisplayIsBuiltin(did) != 0
            let isMain = did == mainID
            let current = currentModeInfo(for: did)
            let modes = availableModeInfos(for: did)
            let brightness = brightnessByUUID[uuid]
            return DisplayInfo(
                id: did,
                uuid: uuid,
                name: name,
                isBuiltIn: isBuiltIn,
                isMain: isMain,
                currentMode: current,
                availableModes: modes,
                softwareBrightness: brightness
            )
        }
    }

    private static func uuidString(for displayID: CGDirectDisplayID) -> String {
        // macOS 14+ Swift overlay: CGDisplayCreateUUIDFromDisplayID → CFUUID?
        // Older SDKs returned Unmanaged<CFUUID>; if compile fails, use .takeRetainedValue().
        guard let cfUUID = CGDisplayCreateUUIDFromDisplayID(displayID) else {
            return String(format: "id-%u", displayID)
        }
        return CFUUIDCreateString(nil, cfUUID) as String
    }

    private static func localizedName(for displayID: CGDirectDisplayID, screens: [NSScreen]) -> String {
        let key = NSDeviceDescriptionKey(rawValue: "NSScreenNumber")
        if let screen = screens.first(where: {
            ($0.deviceDescription[key] as? NSNumber)?.uint32Value == displayID
        }) {
            return screen.localizedName
        }
        if CGDisplayIsBuiltin(displayID) != 0 {
            return "內置螢幕"
        }
        return String(format: "螢幕 %u", displayID)
    }

    private static func currentModeInfo(for displayID: CGDirectDisplayID) -> DisplayModeInfo? {
        // Swift takes ownership of the +1 from Copy; no manual CFRelease.
        guard let mode = CGDisplayCopyDisplayMode(displayID) else { return nil }
        return modeInfo(from: mode)
    }

    private static func availableModeInfos(for displayID: CGDirectDisplayID) -> [DisplayModeInfo] {
        guard let modesCF = CGDisplayCopyAllDisplayModes(displayID, nil) as? [CGDisplayMode] else {
            return []
        }
        var seen = Set<String>()
        var result: [DisplayModeInfo] = []
        for mode in modesCF {
            guard let info = modeInfo(from: mode) else { continue }
            guard info.width >= 800, info.height >= 600 else { continue }
            if seen.contains(info.id) { continue }
            seen.insert(info.id)
            result.append(info)
        }
        result.sort {
            if $0.width != $1.width { return $0.width > $1.width }
            if $0.height != $1.height { return $0.height > $1.height }
            if $0.isHiDPI != $1.isHiDPI { return $0.isHiDPI && !$1.isHiDPI }
            return $0.refreshRate > $1.refreshRate
        }
        return result
    }

    private static func modeInfo(from mode: CGDisplayMode) -> DisplayModeInfo? {
        let pixelW = mode.pixelWidth
        let pixelH = mode.pixelHeight
        let w = mode.width
        let h = mode.height
        guard w > 0, h > 0 else { return nil }
        let refresh = mode.refreshRate
        let isHiDPI = pixelW > w || pixelH > h
        return DisplayModeInfo(
            width: w,
            height: h,
            pixelWidth: pixelW,
            pixelHeight: pixelH,
            refreshRate: refresh,
            isHiDPI: isHiDPI,
            modeIOFlags: mode.ioFlags
        )
    }

    // MARK: - Mode switching

    func apply(mode target: DisplayModeInfo, to display: DisplayInfo) {
        guard !isConfiguring else { return }
        isConfiguring = true
        defer { isConfiguring = false }

        statusMessage = nil
        lastError = nil

        do {
            try Self.configure(displayID: display.id, target: target)
            if let b = brightnessByUUID[display.uuid] {
                try? Self.setGammaBrightness(displayID: display.id, brightness: b)
            }
            refresh()
            statusMessage = "已套用 \(target.title)"
        } catch {
            lastError = error.localizedDescription
            refresh()
        }
    }

    private static func configure(displayID: CGDirectDisplayID, target: DisplayModeInfo) throws {
        guard let modesCF = CGDisplayCopyAllDisplayModes(displayID, nil) as? [CGDisplayMode] else {
            throw DisplayError.modeNotFound
        }

        guard let match = modesCF.first(where: { mode in
            guard let info = modeInfo(from: mode) else { return false }
            return info.width == target.width
                && info.height == target.height
                && info.isHiDPI == target.isHiDPI
                && abs(info.refreshRate - target.refreshRate) < 0.5
        }) else {
            throw DisplayError.modeNotFound
        }

        var config: CGDisplayConfigRef?
        let begin = CGBeginDisplayConfiguration(&config)
        guard begin == .success, let config else {
            throw DisplayError.beginConfigFailed(begin)
        }

        let setErr = CGConfigureDisplayWithDisplayMode(config, displayID, match, nil)
        guard setErr == .success else {
            CGCancelDisplayConfiguration(config)
            throw DisplayError.configurationFailed(setErr)
        }

        let complete = CGCompleteDisplayConfiguration(config, .forSession)
        guard complete == .success else {
            throw DisplayError.configurationFailed(complete)
        }
    }

    func apply(favorite: FavoritePreset) {
        guard let display = displays.first(where: { $0.uuid == favorite.displayUUID })
                ?? displays.first(where: { $0.name == favorite.displayName }) else {
            lastError = DisplayError.displayNotFound.localizedDescription
            return
        }
        guard let mode = display.availableModes.first(where: { favorite.matches($0) }) else {
            lastError = DisplayError.modeNotFound.localizedDescription
            return
        }
        apply(mode: mode, to: display)
    }

    // MARK: - Software brightness (gamma)

    func setSoftwareBrightness(_ value: Double, for display: DisplayInfo) {
        let clamped = min(1, max(0.05, value))
        do {
            try Self.setGammaBrightness(displayID: display.id, brightness: clamped)
            brightnessByUUID[display.uuid] = clamped
            persistBrightnessMap()
            if let idx = displays.firstIndex(where: { $0.id == display.id }) {
                displays[idx].softwareBrightness = clamped
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func resetSoftwareBrightness(for display: DisplayInfo) {
        let err = CGDisplayRestoreColorSyncSettings()
        brightnessByUUID.removeValue(forKey: display.uuid)
        persistBrightnessMap()
        for (uuid, b) in brightnessByUUID {
            if let d = displays.first(where: { $0.uuid == uuid }) {
                try? Self.setGammaBrightness(displayID: d.id, brightness: b)
            }
        }
        refresh()
        if err != .success {
            statusMessage = "已重設亮度（ColorSync restore code \(err.rawValue)）"
        } else {
            statusMessage = "已重設亮度"
        }
    }

    /// red/green/blue Max scaled by brightness; gamma = 1. Approximates a software dimmer.
    private static func setGammaBrightness(displayID: CGDirectDisplayID, brightness: Double) throws {
        let b = Float(brightness)
        let err = CGSetDisplayTransferByFormula(
            displayID,
            0, b, 1,
            0, b, 1,
            0, b, 1
        )
        guard err == .success else {
            throw DisplayError.brightnessFailed(err)
        }
    }

    private func loadBrightnessMap() {
        guard let data = UserDefaults.standard.dictionary(forKey: brightnessDefaultsKey) as? [String: Double] else {
            brightnessByUUID = [:]
            return
        }
        brightnessByUUID = data
    }

    private func persistBrightnessMap() {
        UserDefaults.standard.set(brightnessByUUID, forKey: brightnessDefaultsKey)
    }
}
