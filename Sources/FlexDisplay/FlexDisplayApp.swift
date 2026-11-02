import SwiftUI
import AppKit

@main
struct FlexDisplayApp: App {
    @StateObject private var displayService = DisplayService()
    @StateObject private var favoritesStore = FavoritesStore()
    @StateObject private var blackout = BlackoutController()
    @StateObject private var virtualDisplayService = VirtualDisplayService()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(displayService)
                .environmentObject(favoritesStore)
                .environmentObject(blackout)
                .environmentObject(virtualDisplayService)
                .frame(minWidth: 360, idealWidth: 400, minHeight: 440)
        } label: {
            Label("FlexDisplay", systemImage: "display")
        }
        .menuBarExtraStyle(.window)

        Settings {
            AboutView()
                .environmentObject(virtualDisplayService)
        }
    }
}

struct AboutView: View {
    @EnvironmentObject private var virtuals: VirtualDisplayService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("FlexDisplay")
                .font(.title2.bold())
            Text("類 BetterDisplay 嘅 macOS 選單列螢幕工具（MVP）")
                .foregroundStyle(.secondary)
            Text("版本 1.1.0")
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
            Text("功能：列舉螢幕、切換解像度／刷新率、軟件亮度、常用預設、軟熄屏、實驗性虛擬螢幕。")
                .font(.callout)
            Text(virtuals.spiAvailable
                  ? "CGVirtualDisplay SPI：呢部機／呢個 SDK 有符號（連接仍可能因 entitlement 失敗）。"
                  : "CGVirtualDisplay SPI：符號不可用 — 虛擬螢幕只會儲存設定。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("未包含：DDC/CI、EDID、XDR、PIP 串流。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 380)
    }
}
