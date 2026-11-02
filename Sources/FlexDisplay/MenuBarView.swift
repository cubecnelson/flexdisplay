import SwiftUI
import AppKit
import CoreGraphics

enum SidebarSelection: Hashable {
    case physical(CGDirectDisplayID)
    case virtual(UUID)
}

struct MenuBarView: View {
    @EnvironmentObject private var displays: DisplayService
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var blackout: BlackoutController
    @EnvironmentObject private var virtuals: VirtualDisplayService

    @State private var selection: SidebarSelection?
    @State private var showAbout = false
    @State private var showCreateVirtual = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            banners
            content
            Divider()
            footer
        }
        .background(.background)
        .onAppear {
            displays.refresh()
            if selection == nil {
                if let main = displays.displays.first(where: \.isMain) {
                    selection = .physical(main.id)
                } else if let first = displays.displays.first {
                    selection = .physical(first.id)
                }
            }
        }
        .sheet(isPresented: $showAbout) {
            AboutView()
                .environmentObject(virtuals)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("關閉") { showAbout = false }
                    }
                }
        }
        .sheet(isPresented: $showCreateVirtual) {
            CreateVirtualScreenSheet()
                .environmentObject(displays)
                .environmentObject(virtuals)
        }
    }

    private var header: some View {
        HStack {
            Label("FlexDisplay", systemImage: "display.2")
                .font(.headline)
            Spacer()
            Button {
                showCreateVirtual = true
            } label: {
                Image(systemName: "plus.rectangle.on.rectangle")
            }
            .buttonStyle(.borderless)
            .help("建立虛擬螢幕…")
            Button {
                displays.refresh()
                displays.statusMessage = "已重新整理"
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("重新整理螢幕列表")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var banners: some View {
        if let err = displays.lastError ?? virtuals.lastError {
            errorBanner(err) {
                displays.lastError = nil
                virtuals.lastError = nil
            }
        }
        if let status = displays.statusMessage ?? virtuals.statusMessage {
            statusBanner(status) {
                if displays.statusMessage == status { displays.statusMessage = nil }
                if virtuals.statusMessage == status { virtuals.statusMessage = nil }
            }
        }
    }

    private var content: some View {
        Group {
            if displays.displays.isEmpty && virtuals.screens.isEmpty {
                ContentUnavailableView(
                    "冇螢幕",
                    systemImage: "display.trianglebadge.exclamationmark",
                    description: Text("搵唔到啟用中嘅螢幕。可以建立虛擬螢幕設定。")
                )
                .frame(maxHeight: .infinity)
            } else {
                HStack(alignment: .top, spacing: 0) {
                    displayList
                        .frame(width: 140)
                    Divider()
                    detailPane
                        .frame(maxWidth: .infinity)
                }
                .frame(maxHeight: .infinity)
            }
        }
    }

    private var displayList: some View {
        List(selection: $selection) {
            Section("螢幕") {
                ForEach(displays.displays) { d in
                    HStack(spacing: 6) {
                        Image(systemName: d.isBuiltIn ? "laptopcomputer" : "display")
                            .foregroundStyle(d.isMain ? Color.accentColor : .secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(d.name)
                                .lineLimit(2)
                                .font(.caption.weight(.medium))
                            Text(d.isBuiltIn ? "內置" : "外接")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(SidebarSelection.physical(d.id))
                    .padding(.vertical, 2)
                }
            }

            Section("虛擬") {
                Button {
                    showCreateVirtual = true
                } label: {
                    Label("建立虛擬螢幕…", systemImage: "plus")
                        .font(.caption)
                }
                .buttonStyle(.plain)

                ForEach(virtuals.screens) { v in
                    HStack(spacing: 6) {
                        Image(systemName: v.isAttachedThisSession ? "rectangle.dashed.badge.record" : "rectangle.dashed")
                            .foregroundStyle(v.isAttachedThisSession ? Color.accentColor : .secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(v.name)
                                .lineLimit(2)
                                .font(.caption.weight(.medium))
                            Text(v.isAttachedThisSession ? "已連接" : "已儲存")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(SidebarSelection.virtual(v.id))
                    .padding(.vertical, 2)
                    .contextMenu {
                        if v.isAttachedThisSession {
                            Button("斷開") { virtuals.disconnect(id: v.id) }
                        } else {
                            Button("連接") { virtuals.connect(id: v.id) }
                        }
                        Button("刪除", role: .destructive) {
                            if case .virtual(let id) = selection, id == v.id {
                                selection = nil
                            }
                            virtuals.remove(id: v.id)
                        }
                    }
                }
            }

            if !favorites.favorites.isEmpty {
                Section("常用") {
                    ForEach(favorites.favorites) { fav in
                        Button {
                            displays.apply(favorite: fav)
                        } label: {
                            Text(fav.title)
                                .font(.caption2)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("刪除", role: .destructive) {
                                favorites.remove(fav)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private var detailPane: some View {
        switch selection {
        case .physical(let id):
            if let display = displays.displays.first(where: { $0.id == id }) {
                DisplayDetailView(display: display)
            } else {
                placeholder("揀一個螢幕")
            }
        case .virtual(let id):
            VirtualScreenDetailView(configID: id)
        case .none:
            placeholder("揀一個螢幕")
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            Button("關於") { showAbout = true }
                .buttonStyle(.borderless)
            Button("建立虛擬螢幕…") { showCreateVirtual = true }
                .buttonStyle(.borderless)
            Spacer()
            Button("結束") {
                // Tear down virtuals before quit
                for v in virtuals.screens where v.isAttachedThisSession {
                    virtuals.disconnect(id: v.id)
                }
                blackout.dismiss()
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.red)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .font(.callout)
    }

    private func errorBanner(_ text: String, clear: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(text)
                .font(.caption)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
            Button(action: clear) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(Color.red.opacity(0.12))
    }

    private func statusBanner(_ text: String, clear: @escaping () -> Void) -> some View {
        HStack {
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .onAppear {
            Task {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                clear()
            }
        }
    }
}
