import Foundation
import CoreGraphics
import AppKit
import Combine
import Darwin

/// Experimental virtual displays via `CGVirtualDisplay*` (dlsym into CoreGraphics).
/// Stock public SDK often lacks linkable symbols / entitlements — configs still persist.
@MainActor
final class VirtualDisplayService: ObservableObject {
    @Published private(set) var screens: [VirtualScreenConfig] = []
    @Published var lastError: String?
    @Published var statusMessage: String?
    /// True when dlsym resolved the create/mode entry points.
    @Published private(set) var spiAvailable: Bool = false

    private let defaultsKey = "flexdisplay.virtualScreens.v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// Keep CGVirtualDisplay objects alive for the session (keyed by config id).
    private var liveDisplays: [UUID: AnyObject] = [:]

    private let spi = CGVirtualDisplaySPI.shared

    init() {
        spiAvailable = spi.isAvailable
        load()
        // Session restart: nothing is attached until user reconnects.
        for i in screens.indices {
            screens[i].isAttachedThisSession = false
            screens[i]._attachedDisplayID = nil
        }
    }

    // MARK: - Persistence

    func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else {
            screens = []
            return
        }
        do {
            screens = try decoder.decode([VirtualScreenConfig].self, from: data)
        } catch {
            screens = []
        }
    }

    func save() {
        // Don't persist session-only flags as attached
        var copy = screens
        for i in copy.indices {
            copy[i].isAttachedThisSession = false
            // Keep last known ID as hint only
        }
        do {
            let data = try encoder.encode(copy)
            UserDefaults.standard.set(data, forKey: defaultsKey)
        } catch {
            // ignore
        }
    }

    // MARK: - CRUD

    /// Persist a new recipe and attempt system attach.
    @discardableResult
    func create(_ draft: VirtualScreenConfig, attemptAttach: Bool = true) -> VirtualScreenConfig {
        var config = draft
        if config.width < 640 || config.height < 480 {
            lastError = VirtualDisplayError.invalidSize.localizedDescription
            return draft
        }
        screens.insert(config, at: 0)
        save()

        if attemptAttach {
            connect(id: config.id)
            if let updated = screens.first(where: { $0.id == config.id }) {
                config = updated
            }
        } else {
            statusMessage = "已儲存虛擬螢幕設定"
        }
        return config
    }

    func update(_ config: VirtualScreenConfig) {
        guard let idx = screens.firstIndex(where: { $0.id == config.id }) else { return }
        var next = config
        // Preserve session attachment state from store
        next.isAttachedThisSession = screens[idx].isAttachedThisSession
        next._attachedDisplayID = screens[idx]._attachedDisplayID
        screens[idx] = next
        save()
    }

    func remove(id: UUID) {
        disconnect(id: id)
        screens.removeAll { $0.id == id }
        save()
        statusMessage = "已刪除虛擬螢幕"
    }

    // MARK: - Connect / Disconnect

    func connect(id: UUID) {
        lastError = nil
        guard let idx = screens.firstIndex(where: { $0.id == id }) else { return }
        var config = screens[idx]

        guard spi.isAvailable else {
            lastError = VirtualDisplayError.symbolsUnavailable.localizedDescription
            statusMessage = nil
            return
        }

        do {
            let (displayObj, displayID) = try spi.createDisplay(from: config)
            liveDisplays[config.id] = displayObj
            config._attachedDisplayID = displayID
            config.isAttachedThisSession = true
            screens[idx] = config
            save()

            if config.mirrorToCompanion {
                try applyMirror(virtualID: displayID, companionUUID: config.companionDisplayUUID)
            }

            statusMessage = "虛擬螢幕已連接（ID \(displayID)）"
            // Notify system display list listeners
            NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        } catch let err as VirtualDisplayError {
            lastError = err.localizedDescription
        } catch {
            lastError = error.localizedDescription
        }
    }

    func disconnect(id: UUID) {
        if let obj = liveDisplays.removeValue(forKey: id) {
            // Dropping the last strong ref typically tears down the virtual display.
            _ = obj
        }
        if let idx = screens.firstIndex(where: { $0.id == id }) {
            screens[idx].isAttachedThisSession = false
            screens[idx]._attachedDisplayID = nil
            save()
        }
        statusMessage = "已斷開虛擬螢幕"
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    /// Change resolution of an attached virtual display by recreating modes (best-effort).
    func applyResolution(id: UUID, width: Int, height: Int, refreshRate: Double, isHiDPI: Bool) {
        guard width >= 640, height >= 480 else {
            lastError = VirtualDisplayError.invalidSize.localizedDescription
            return
        }
        guard let idx = screens.firstIndex(where: { $0.id == id }) else { return }
        screens[idx].width = width
        screens[idx].height = height
        screens[idx].refreshRate = refreshRate
        screens[idx].isHiDPI = isHiDPI
        save()

        let wasAttached = screens[idx].isAttachedThisSession
        if wasAttached {
            disconnect(id: id)
            connect(id: id)
        } else {
            statusMessage = "已更新虛擬解像度（未連接）"
        }
    }

    func setMirror(id: UUID, enabled: Bool) {
        guard let idx = screens.firstIndex(where: { $0.id == id }) else { return }
        screens[idx].mirrorToCompanion = enabled
        save()
        guard screens[idx].isAttachedThisSession,
              let vid = screens[idx].attachedDisplayID else { return }
        do {
            if enabled {
                try applyMirror(virtualID: vid, companionUUID: screens[idx].companionDisplayUUID)
                statusMessage = "已啟用鏡像"
            } else {
                try clearMirror(virtualID: vid)
                statusMessage = "已取消鏡像"
            }
        } catch let err as VirtualDisplayError {
            lastError = err.localizedDescription
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Mirror helpers

    private func applyMirror(virtualID: CGDirectDisplayID, companionUUID: String?) throws {
        guard let companionUUID,
              let companion = resolveCompanionID(uuid: companionUUID) else {
            throw VirtualDisplayError.companionMissing
        }
        var config: CGDisplayConfigRef?
        let begin = CGBeginDisplayConfiguration(&config)
        guard begin == .success, let config else {
            throw VirtualDisplayError.mirrorFailed(begin)
        }
        // Mirror virtual *of* companion (virtual shows companion's content).
        let err = CGConfigureDisplayMirrorOfDisplay(config, virtualID, companion)
        guard err == .success else {
            CGCancelDisplayConfiguration(config)
            throw VirtualDisplayError.mirrorFailed(err)
        }
        let complete = CGCompleteDisplayConfiguration(config, .forSession)
        guard complete == .success else {
            throw VirtualDisplayError.mirrorFailed(complete)
        }
    }

    private func clearMirror(virtualID: CGDirectDisplayID) throws {
        var config: CGDisplayConfigRef?
        let begin = CGBeginDisplayConfiguration(&config)
        guard begin == .success, let config else {
            throw VirtualDisplayError.mirrorFailed(begin)
        }
        let err = CGConfigureDisplayMirrorOfDisplay(config, virtualID, kCGNullDirectDisplay)
        guard err == .success else {
            CGCancelDisplayConfiguration(config)
            throw VirtualDisplayError.mirrorFailed(err)
        }
        let complete = CGCompleteDisplayConfiguration(config, .forSession)
        guard complete == .success else {
            throw VirtualDisplayError.mirrorFailed(complete)
        }
    }

    private func resolveCompanionID(uuid: String) -> CGDirectDisplayID? {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        for did in ids.prefix(Int(count)) {
            if uuidString(for: did) == uuid { return did }
        }
        return nil
    }

    private func uuidString(for displayID: CGDirectDisplayID) -> String {
        guard let cfUUID = CGDisplayCreateUUIDFromDisplayID(displayID) else {
            return String(format: "id-%u", displayID)
        }
        return CFUUIDCreateString(nil, cfUUID) as String
    }
}

// MARK: - dlsym SPI bridge

/// Dynamically resolves undocumented CGVirtualDisplay* symbols from CoreGraphics.
final class CGVirtualDisplaySPI: @unchecked Sendable {
    static let shared = CGVirtualDisplaySPI()

    private let handle: UnsafeMutableRawPointer?

    // Function pointer types (ObjC-ish APIs; use raw pointers / Unmanaged).
    private typealias DescriptorCreateFn = @convention(c) (CFAllocator?) -> UnsafeMutableRawPointer?
    private typealias SetNameFn = @convention(c) (UnsafeMutableRawPointer?, CFString?) -> Void
    private typealias SetUIntFn = @convention(c) (UnsafeMutableRawPointer?, Int) -> Void
    private typealias SetDoubleFn = @convention(c) (UnsafeMutableRawPointer?, Double) -> Void
    private typealias SetQueueFn = @convention(c) (UnsafeMutableRawPointer?, DispatchQueue?) -> Void
    private typealias SetSizeFn = @convention(c) (UnsafeMutableRawPointer?, CGSize) -> Void
    private typealias ModeCreateFn = @convention(c) (CFAllocator?, Int, Int, Double) -> UnsafeMutableRawPointer?
    private typealias DisplayCreateFn = @convention(c) (UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
    private typealias SetModesFn = @convention(c) (UnsafeMutableRawPointer?, CFArray?) -> Bool
    private typealias GetDisplayIDFn = @convention(c) (UnsafeMutableRawPointer?) -> UInt32

    private let descriptorCreate: DescriptorCreateFn?
    private let setName: SetNameFn?
    private let setMaxPixelsWide: SetUIntFn?
    private let setMaxPixelsHigh: SetUIntFn?
    private let setQueue: SetQueueFn?
    private let setSizeInMillimeters: SetSizeFn?
    private let modeCreate: ModeCreateFn?
    private let displayCreate: DisplayCreateFn?
    private let setModes: SetModesFn?
    private let getDisplayID: GetDisplayIDFn?

    var isAvailable: Bool {
        descriptorCreate != nil
            && displayCreate != nil
            && modeCreate != nil
            && setModes != nil
            && getDisplayID != nil
            && setMaxPixelsWide != nil
            && setMaxPixelsHigh != nil
    }

    private init() {
        handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY)

        func sym<T>(_ name: String) -> T? {
            guard let handle,
                  let ptr = dlsym(handle, name) else { return nil }
            return unsafeBitCast(ptr, to: T.self)
        }

        descriptorCreate = sym("CGVirtualDisplayDescriptorCreate")
        setName = sym("CGVirtualDisplayDescriptorSetName")
        setMaxPixelsWide = sym("CGVirtualDisplayDescriptorSetMaxPixelsWide")
        setMaxPixelsHigh = sym("CGVirtualDisplayDescriptorSetMaxPixelsHigh")
        setQueue = sym("CGVirtualDisplayDescriptorSetQueue")
        setSizeInMillimeters = sym("CGVirtualDisplayDescriptorSetSizeInMillimeters")
        modeCreate = sym("CGVirtualDisplayModeCreate")
        displayCreate = sym("CGVirtualDisplayCreate")
        setModes = sym("CGVirtualDisplaySetModes")
        getDisplayID = sym("CGVirtualDisplayGetDisplayID")
    }

    /// Create + set modes; returns retained ObjC object + CGDirectDisplayID.
    func createDisplay(from config: VirtualScreenConfig) throws -> (AnyObject, CGDirectDisplayID) {
        guard isAvailable,
              let descriptorCreate,
              let displayCreate,
              let modeCreate,
              let setModes,
              let getDisplayID,
              let setMaxPixelsWide,
              let setMaxPixelsHigh else {
            throw VirtualDisplayError.symbolsUnavailable
        }

        guard let desc = descriptorCreate(kCFAllocatorDefault) else {
            throw VirtualDisplayError.createFailed
        }

        let pointW = config.width
        let pointH = config.height
        let pixelW = config.isHiDPI ? pointW * 2 : pointW
        let pixelH = config.isHiDPI ? pointH * 2 : pointH

        setMaxPixelsWide(desc, pixelW)
        setMaxPixelsHigh(desc, pixelH)
        setName?(desc, config.name as CFString)
        setQueue?(desc, DispatchQueue.main)

        // ~96 dpi heuristic for mm size (points as 1/72" is wrong for displays;
        // use pixel diagonal with 110 dpi assumption for a plausible panel size).
        let mmW = CGFloat(pixelW) / 110.0 * 25.4
        let mmH = CGFloat(pixelH) / 110.0 * 25.4
        setSizeInMillimeters?(desc, CGSize(width: mmW, height: mmH))

        guard let modePtr = modeCreate(kCFAllocatorDefault, pointW, pointH, config.refreshRate) else {
            throw VirtualDisplayError.modeFailed
        }

        // Build CFArray of mode object(s). Point-size mode; HiDPI is expressed via max pixels.
        let modeObj = Unmanaged<AnyObject>.fromOpaque(modePtr).takeUnretainedValue()
        var modeObjects: [AnyObject] = [modeObj]
        // Optional second mode at half linear size helps some hosts pick a LoDPI fallback.
        if config.isHiDPI,
           let lo = modeCreate(kCFAllocatorDefault, max(640, pointW / 2), max(480, pointH / 2), config.refreshRate) {
            modeObjects.append(Unmanaged<AnyObject>.fromOpaque(lo).takeUnretainedValue())
        }
        let modes = modeObjects as CFArray

        guard let displayPtr = displayCreate(desc) else {
            throw VirtualDisplayError.createFailed
        }

        let ok = setModes(displayPtr, modes)
        guard ok else {
            throw VirtualDisplayError.modeFailed
        }

        let displayID = getDisplayID(displayPtr)
        guard displayID != 0, displayID != kCGNullDirectDisplay else {
            throw VirtualDisplayError.createFailed
        }

        // Create → +1; transfer to ARC and keep in liveDisplays.
        let obj = Unmanaged<AnyObject>.fromOpaque(displayPtr).takeRetainedValue()
        return (obj, CGDirectDisplayID(displayID))
    }
}
