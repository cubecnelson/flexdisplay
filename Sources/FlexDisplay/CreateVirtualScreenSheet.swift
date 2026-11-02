import SwiftUI
import CoreGraphics

struct CreateVirtualScreenSheet: View {
    @EnvironmentObject private var displays: DisplayService
    @EnvironmentObject private var virtuals: VirtualDisplayService
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = "虛擬螢幕"
    @State private var width: Int = 1920
    @State private var height: Int = 1080
    @State private var refreshRate: Double = 60
    @State private var isHiDPI: Bool = true
    @State private var companionID: CGDirectDisplayID?
    @State private var mirrorToCompanion: Bool = false
    @State private var attemptAttach: Bool = true

    private let presets: [(String, Int, Int)] = [
        ("1080p", 1920, 1080),
        ("1440p", 2560, 1440),
        ("4K", 3840, 2160),
        ("iPad", 2360, 1640),
        ("手機直", 1170, 2532),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("建立虛擬螢幕")
                .font(.title2.bold())

            if !virtuals.spiAvailable {
                Label(
                    "系統未匯出 CGVirtualDisplay 符號；可以儲存設定，但未必連接成功。",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }

            Form {
                TextField("名稱", text: $name)

                Picker("配合實體螢幕", selection: $companionID) {
                    Text("唔指定").tag(Optional<CGDirectDisplayID>.none)
                    ForEach(displays.displays) { d in
                        Text(d.name).tag(Optional(d.id))
                    }
                }
                .onChange(of: companionID) { _, newID in
                    matchAspect(to: newID)
                }

                HStack {
                    Text("預設")
                    ForEach(presets, id: \.0) { p in
                        Button(p.0) {
                            width = p.1
                            height = p.2
                        }
                        .controlSize(.small)
                    }
                }

                HStack {
                    Text("闊")
                    TextField("", value: $width, format: .number)
                        .frame(width: 80)
                    Text("高")
                    TextField("", value: $height, format: .number)
                        .frame(width: 80)
                }

                HStack {
                    Text("刷新率")
                    TextField("", value: $refreshRate, format: .number)
                        .frame(width: 60)
                    Text("Hz")
                    Toggle("HiDPI", isOn: $isHiDPI)
                }

                Toggle("連接後鏡像到實體螢幕", isOn: $mirrorToCompanion)
                    .disabled(companionID == nil)

                Toggle("立即嘗試連接系統虛擬螢幕", isOn: $attemptAttach)

                HStack(alignment: .top) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("串流／全螢幕畫面")
                            .font(.callout)
                        Text("稍後／需要螢幕錄製權限")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: .constant(false))
                        .disabled(true)
                        .labelsHidden()
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("建立") { create() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear {
            if companionID == nil {
                companionID = displays.displays.first(where: \.isMain)?.id
                    ?? displays.displays.first?.id
            }
            matchAspect(to: companionID)
        }
    }

    private func matchAspect(to id: CGDirectDisplayID?) {
        guard let id,
              let d = displays.displays.first(where: { $0.id == id }),
              let mode = d.currentMode else { return }
        width = mode.width
        height = mode.height
        refreshRate = mode.refreshRate > 0 ? mode.refreshRate : 60
        isHiDPI = mode.isHiDPI
    }

    private func create() {
        let companion = companionID.flatMap { id in displays.displays.first { $0.id == id } }
        var draft = VirtualScreenConfig.draft(matching: companion, defaultName: name.isEmpty ? "虛擬螢幕" : name)
        draft.width = width
        draft.height = height
        draft.refreshRate = refreshRate
        draft.isHiDPI = isHiDPI
        draft.mirrorToCompanion = mirrorToCompanion && companion != nil
        draft.streamEnabled = false
        _ = virtuals.create(draft, attemptAttach: attemptAttach)
        dismiss()
    }
}
