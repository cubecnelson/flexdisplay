import SwiftUI

struct VirtualScreenDetailView: View {
    @EnvironmentObject private var virtuals: VirtualDisplayService
    @EnvironmentObject private var displays: DisplayService

    let configID: UUID

    @State private var widthSlider: Double = 1920
    @State private var heightRatioLocked: Bool = true

    private var config: VirtualScreenConfig? {
        virtuals.screens.first { $0.id == configID }
    }

    var body: some View {
        Group {
            if let config {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        header(config)
                        statusBox(config)
                        resolutionBox(config)
                        actionsBox(config)
                        noteBox
                    }
                    .padding(12)
                }
                .onAppear {
                    widthSlider = Double(config.width)
                }
                .onChange(of: config.width) { _, w in
                    widthSlider = Double(w)
                }
            } else {
                Text("虛擬螢幕已唔存在")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func header(_ config: VirtualScreenConfig) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "rectangle.dashed")
                    .foregroundStyle(Color.accentColor)
                Text(config.name)
                    .font(.title3.weight(.semibold))
            }
            Text(config.sizeLabel)
                .font(.callout)
                .foregroundStyle(.secondary)
            if let cName = config.companionDisplayName {
                Text("關聯：\(cName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func statusBox(_ config: VirtualScreenConfig) -> some View {
        GroupBox("狀態") {
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent("連接") {
                    Text(config.statusLabel)
                }
                if let did = config.attachedDisplayID {
                    LabeledContent("Display ID") {
                        Text("\(did)")
                            .font(.system(.body, design: .monospaced))
                    }
                }
                LabeledContent("SPI") {
                    Text(virtuals.spiAvailable ? "符號可用" : "符號不可用")
                }
                .font(.callout)
            }
        }
    }

    private func resolutionBox(_ config: VirtualScreenConfig) -> some View {
        GroupBox("解像度（虛擬來源）") {
            VStack(alignment: .leading, spacing: 10) {
                Text("闊 \(Int(widthSlider.rounded())) pt")
                    .font(.callout.monospacedDigit())
                Slider(value: $widthSlider, in: 800...3840, step: 16)
                Toggle("保持比例", isOn: $heightRatioLocked)
                HStack {
                    Button("套用解像度") {
                        applySlider(config)
                    }
                    .controlSize(.small)
                    Spacer()
                    Text(config.isHiDPI ? "HiDPI 開" : "HiDPI 關")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func actionsBox(_ config: VirtualScreenConfig) -> some View {
        GroupBox("操作") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    if config.isAttachedThisSession {
                        Button("斷開") {
                            virtuals.disconnect(id: config.id)
                        }
                    } else {
                        Button("連接") {
                            virtuals.connect(id: config.id)
                        }
                        .disabled(!virtuals.spiAvailable)
                    }
                    Button("刪除", role: .destructive) {
                        virtuals.remove(id: config.id)
                    }
                    Spacer()
                }

                Toggle("鏡像到實體螢幕", isOn: Binding(
                    get: { config.mirrorToCompanion },
                    set: { virtuals.setMirror(id: config.id, enabled: $0) }
                ))
                .disabled(config.companionDisplayUUID == nil)

                HStack(alignment: .top) {
                    Toggle("串流到實體螢幕", isOn: .constant(false))
                        .disabled(true)
                    Text("稍後／需要螢幕錄製權限")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var noteBox: some View {
        Text("虛擬螢幕依賴 CoreGraphics 未公開／半公開 API（CGVirtualDisplay）。Stock SDK 可能得儲存設定而連接唔到；真正系統虛擬桌面往往要額外 entitlement 或 private framework。")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    private func applySlider(_ config: VirtualScreenConfig) {
        let w = Int(widthSlider.rounded())
        let h: Int
        if heightRatioLocked, config.width > 0 {
            h = max(480, Int((Double(config.height) * Double(w) / Double(config.width)).rounded()))
        } else {
            h = config.height
        }
        virtuals.applyResolution(
            id: config.id,
            width: w,
            height: h,
            refreshRate: config.refreshRate,
            isHiDPI: config.isHiDPI
        )
    }
}
