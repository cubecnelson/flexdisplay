import SwiftUI

struct DisplayDetailView: View {
    @EnvironmentObject private var displays: DisplayService
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var blackout: BlackoutController

    let display: DisplayInfo

    @State private var brightnessSlider: Double = 1.0

    private var isBlackedOut: Bool {
        blackout.activeDisplayID == display.id
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                headerBlock
                currentBlock
                brightnessBlock
                modesBlock
                actionsBlock
            }
            .padding(12)
        }
        .onAppear {
            brightnessSlider = display.softwareBrightness ?? 1.0
        }
        .onChange(of: display.id) { _, _ in
            brightnessSlider = display.softwareBrightness ?? 1.0
        }
        .onChange(of: display.softwareBrightness) { _, newValue in
            if let newValue {
                brightnessSlider = newValue
            }
        }
    }

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(display.name)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                Spacer()
                if display.isMain {
                    Text("主螢幕")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.2))
                        .clipShape(Capsule())
                }
            }
            Text(display.isBuiltIn ? "內置顯示器" : "外接顯示器")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(display.uuid)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var currentBlock: some View {
        GroupBox("目前") {
            if let mode = display.currentMode {
                VStack(alignment: .leading, spacing: 4) {
                    LabeledContent("解像度") {
                        Text("\(mode.width)×\(mode.height)")
                    }
                    LabeledContent("像素") {
                        Text("\(mode.pixelWidth)×\(mode.pixelHeight)")
                    }
                    LabeledContent("刷新率") {
                        Text(mode.refreshRateLabel)
                    }
                    LabeledContent("HiDPI") {
                        Text(mode.isHiDPI ? "係" : "否")
                    }
                }
                .font(.callout)
            } else {
                Text("無法讀取目前模式")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var brightnessBlock: some View {
        GroupBox("亮度（軟件／伽瑪）") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(Int((brightnessSlider * 100).rounded()))%")
                        .font(.system(.body, design: .rounded).monospacedDigit())
                        .frame(width: 44, alignment: .leading)
                    Slider(value: $brightnessSlider, in: 0.05...1.0, step: 0.01) {
                        Text("亮度")
                    } onEditingChanged: { editing in
                        // Apply on release; also apply mid-drag via continuous binding below
                        if !editing {
                            displays.setSoftwareBrightness(brightnessSlider, for: display)
                        }
                    }
                }
                .onChange(of: brightnessSlider) { _, newValue in
                    displays.setSoftwareBrightness(newValue, for: display)
                }
                HStack {
                    Button("重設亮度") {
                        brightnessSlider = 1.0
                        displays.resetSoftwareBrightness(for: display)
                    }
                    .controlSize(.small)
                    Spacer()
                    Text("唔會改硬件背光")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var modesBlock: some View {
        GroupBox("解像度") {
            if display.availableModes.isEmpty {
                Text("冇可用模式")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(display.availableModes) { mode in
                        modeRow(mode)
                        if mode.id != display.availableModes.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func modeRow(_ mode: DisplayModeInfo) -> some View {
        let isCurrent = display.currentMode?.id == mode.id
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(mode.title)
                    .font(.callout.weight(isCurrent ? .semibold : .regular))
                Text(mode.pointSizeDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isCurrent {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
            }
            Button {
                displays.apply(mode: mode, to: display)
            } label: {
                Text(isCurrent ? "套用中" : "套用")
            }
            .controlSize(.small)
            .disabled(isCurrent)
            Button {
                _ = favorites.add(from: display, mode: mode)
                displays.statusMessage = "已加入常用"
            } label: {
                Image(systemName: "star")
            }
            .controlSize(.small)
            .buttonStyle(.borderless)
            .help("加入常用")
        }
        .padding(.vertical, 6)
    }

    private var actionsBlock: some View {
        GroupBox("操作") {
            HStack {
                Button {
                    blackout.toggle(for: display)
                } label: {
                    Label(
                        isBlackedOut ? "解除熄屏" : "熄屏",
                        systemImage: isBlackedOut ? "sun.max" : "moon.fill"
                    )
                }
                .controlSize(.regular)
                Spacer()
            }
        }
    }
}
