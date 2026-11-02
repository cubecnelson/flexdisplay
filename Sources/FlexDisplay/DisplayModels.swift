import Foundation
import CoreGraphics
import AppKit

/// Snapshot of one physical display and its current mode.
struct DisplayInfo: Identifiable, Hashable {
    let id: CGDirectDisplayID
    let uuid: String
    let name: String
    let isBuiltIn: Bool
    let isMain: Bool
    let currentMode: DisplayModeInfo?
    let availableModes: [DisplayModeInfo]
    /// Software brightness 0...1 (gamma). Nil means system default / untouched.
    var softwareBrightness: Double?

    var summaryLine: String {
        guard let mode = currentMode else { return name }
        let hi = mode.isHiDPI ? " HiDPI" : ""
        return "\(name) · \(mode.width)×\(mode.height)@\(mode.refreshRateLabel)\(hi)"
    }
}

/// One CGDisplayMode, filtered for UI presentation.
struct DisplayModeInfo: Identifiable, Hashable, Codable {
    /// Synthetic id: "WxH@R-hi|lo"
    var id: String { "\(width)x\(height)@\(String(format: "%.2f", refreshRate))-\(isHiDPI ? "hi" : "lo")" }

    let width: Int
    let height: Int
    let pixelWidth: Int
    let pixelHeight: Int
    let refreshRate: Double
    let isHiDPI: Bool
    /// Opaque handle index into the live mode list (not persisted).
    let modeIOFlags: UInt32

    var refreshRateLabel: String {
        if refreshRate <= 0 { return "—" }
        if abs(refreshRate - refreshRate.rounded()) < 0.05 {
            return "\(Int(refreshRate.rounded()))Hz"
        }
        return String(format: "%.2fHz", refreshRate)
    }

    var title: String {
        let hi = isHiDPI ? " · HiDPI" : ""
        return "\(width)×\(height) @ \(refreshRateLabel)\(hi)"
    }

    var pointSizeDescription: String {
        "\(width)×\(height) pt · \(pixelWidth)×\(pixelHeight) px"
    }
}

/// Persisted favorite resolution preset.
struct FavoritePreset: Identifiable, Hashable, Codable {
    var id: UUID
    var displayUUID: String
    var displayName: String
    var width: Int
    var height: Int
    var refreshRate: Double
    var isHiDPI: Bool
    var createdAt: Date

    var title: String {
        let hi = isHiDPI ? " HiDPI" : ""
        let hz: String
        if refreshRate <= 0 {
            hz = ""
        } else if abs(refreshRate - refreshRate.rounded()) < 0.05 {
            hz = "@\(Int(refreshRate.rounded()))Hz"
        } else {
            hz = String(format: "@%.2fHz", refreshRate)
        }
        return "\(displayName) · \(width)×\(height)\(hz)\(hi)"
    }

    func matches(_ mode: DisplayModeInfo) -> Bool {
        mode.width == width
            && mode.height == height
            && mode.isHiDPI == isHiDPI
            && abs(mode.refreshRate - refreshRate) < 0.5
    }
}

enum DisplayError: LocalizedError {
    case noDisplays
    case modeNotFound
    case configurationFailed(CGError)
    case beginConfigFailed(CGError)
    case brightnessFailed(CGError)
    case displayNotFound

    var errorDescription: String? {
        switch self {
        case .noDisplays:
            return "搵唔到啟用中嘅螢幕。"
        case .modeNotFound:
            return "搵唔到指定嘅解像度模式。"
        case .configurationFailed(let err):
            return "切換解像度失敗（CGError \(err.rawValue)）。"
        case .beginConfigFailed(let err):
            return "無法開始螢幕設定（CGError \(err.rawValue)）。"
        case .brightnessFailed(let err):
            return "調整軟件亮度失敗（CGError \(err.rawValue)）。"
        case .displayNotFound:
            return "指定嘅螢幕已經唔存在。"
        }
    }
}
