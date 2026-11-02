import AppKit
import SwiftUI
import Combine

/// Full-screen black borderless window on a chosen display (soft blackout).
@MainActor
final class BlackoutController: ObservableObject {
    @Published private(set) var activeDisplayID: CGDirectDisplayID?

    private var window: NSWindow?
    private var escapeMonitor: Any?

    var isActive: Bool { activeDisplayID != nil }

    func toggle(for display: DisplayInfo) {
        if activeDisplayID == display.id {
            dismiss()
        } else {
            present(on: display)
        }
    }

    func present(on display: DisplayInfo) {
        dismiss()

        guard let screen = screen(for: display.id) else { return }

        let win = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        win.isReleasedWhenClosed = false
        win.level = .screenSaver
        win.isOpaque = true
        win.backgroundColor = .black
        win.hasShadow = false
        win.ignoresMouseEvents = false
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        win.contentView = NSHostingView(rootView: BlackoutContentView {
            self.dismiss()
        })
        // Place exactly on that display
        win.setFrame(screen.frame, display: true)
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                self?.dismiss()
                return nil
            }
            return event
        }

        window = win
        activeDisplayID = display.id
    }

    func dismiss() {
        if let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
            escapeMonitor = nil
        }
        window?.orderOut(nil)
        window?.close()
        window = nil
        activeDisplayID = nil
    }

    private func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        let key = NSDeviceDescriptionKey(rawValue: "NSScreenNumber")
        return NSScreen.screens.first {
            ($0.deviceDescription[key] as? NSNumber)?.uint32Value == displayID
        }
    }
}

private struct BlackoutContentView: View {
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 12) {
                Text("熄屏中")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Text("撳 Esc 或「解除熄屏」退出")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.45))
                Button("解除熄屏") {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)
                .padding(.top, 8)
            }
            .opacity(0.85)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            onDismiss()
        }
    }
}
