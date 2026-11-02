import Foundation
import CoreGraphics

/// Persisted virtual-screen recipe (may or may not be attached as a system display).
struct VirtualScreenConfig: Identifiable, Hashable, Codable {
    var id: UUID
    var name: String
    var width: Int
    var height: Int
    var refreshRate: Double
    var isHiDPI: Bool
    /// Physical display UUID to associate / aspect-match.
    var companionDisplayUUID: String?
    var companionDisplayName: String?
    /// When true, attempt CGConfigureDisplayMirrorOfDisplay(virtual → companion).
    var mirrorToCompanion: Bool
    /// Full-screen stream / PIP — stub until Screen Recording permission path exists.
    var streamEnabled: Bool
    var createdAt: Date

    /// Runtime-only: system display ID if CGVirtualDisplay attached this session.
    var attachedDisplayID: CGDirectDisplayID? {
        get { _attachedDisplayID.flatMap { CGDirectDisplayID(exactly: $0) } }
        set { _attachedDisplayID = newValue.map { UInt32($0) } }
    }

    /// Codable stand-in (CGDirectDisplayID is not Codable across sessions usefully;
    /// we still persist last known ID for UI hints, but attachment is session-scoped).
    var _attachedDisplayID: UInt32?
    var isAttachedThisSession: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, name, width, height, refreshRate, isHiDPI
        case companionDisplayUUID, companionDisplayName
        case mirrorToCompanion, streamEnabled, createdAt
        case _attachedDisplayID
    }

    var sizeLabel: String {
        let hi = isHiDPI ? " HiDPI" : ""
        let hz: String
        if refreshRate <= 0 {
            hz = ""
        } else if abs(refreshRate - refreshRate.rounded()) < 0.05 {
            hz = "@\(Int(refreshRate.rounded()))Hz"
        } else {
            hz = String(format: "@%.2fHz", refreshRate)
        }
        return "\(width)×\(height)\(hz)\(hi)"
    }

    var statusLabel: String {
        if isAttachedThisSession { return "已連接" }
        return "已儲存（未連接）"
    }

    static func draft(
        matching physical: DisplayInfo?,
        defaultName: String = "虛擬螢幕"
    ) -> VirtualScreenConfig {
        let w = physical?.currentMode?.width ?? 1920
        let h = physical?.currentMode?.height ?? 1080
        let r = physical?.currentMode?.refreshRate ?? 60
        let hi = physical?.currentMode?.isHiDPI ?? true
        return VirtualScreenConfig(
            id: UUID(),
            name: defaultName,
            width: w,
            height: h,
            refreshRate: r > 0 ? r : 60,
            isHiDPI: hi,
            companionDisplayUUID: physical?.uuid,
            companionDisplayName: physical?.name,
            mirrorToCompanion: false,
            streamEnabled: false,
            createdAt: Date(),
            _attachedDisplayID: nil,
            isAttachedThisSession: false
        )
    }
}

enum VirtualDisplayError: LocalizedError {
    case symbolsUnavailable
    case createFailed
    case modeFailed
    case notAttached
    case companionMissing
    case mirrorFailed(CGError)
    case invalidSize

    var errorDescription: String? {
        switch self {
        case .symbolsUnavailable:
            return "此 macOS／SDK 未能建立系統虛擬螢幕；已儲存設定。請用有開發者 entitlements 嘅 build 或之後接 private API。"
        case .createFailed:
            return "建立虛擬螢幕失敗（CGVirtualDisplayCreate 回傳空）。已儲存設定。"
        case .modeFailed:
            return "設定虛擬螢幕模式失敗；已儲存設定。"
        case .notAttached:
            return "呢個虛擬螢幕而家未連接。"
        case .companionMissing:
            return "搵唔到關聯嘅實體螢幕。"
        case .mirrorFailed(let err):
            return "鏡像設定失敗（CGError \(err.rawValue)）。"
        case .invalidSize:
            return "闊／高無效（最少 640×480）。"
        }
    }
}
