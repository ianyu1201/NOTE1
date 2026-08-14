import SwiftUI
import UIKit

struct V02CardPreviewView: View {
    @ObservedObject var store: V02Store
    let showSettings: () -> Void
    let showTrash: () -> Void
    let showHistory: () -> Void
    let showSearch: () -> Void
    let reportError: (Error) -> Void
    let onEditingChange: (Bool) -> Void
    let onOverlayChange: (Bool) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0
    @AppStorage("v02.cardPreview.currentID") private var persistedCardID = ""
    @State private var undoTuckedInspiration: V02Inspiration?
    @State private var editingInspiration: V02Inspiration?
    @State private var isShowingCollectionPicker = false
    @State private var isShowingCreateCollection = false
    @State private var pendingInspirationID: UUID?
    @State private var newCollectionName = ""

    private var cards: [V02CardPreviewEntry] { store.cardPreviewEntries }

    private var emptyStateMessage: String {
        store.activeCollections.isEmpty
            ? "收起的灵感仍可在“灵感”中找到。"
            : "构思中的内容请前往“构思集”继续调整。"
    }

    var body: some View {
        NavigationStack {
        ZStack(alignment: .top) {
            NoteTheme.canvas.ignoresSafeArea()
            VStack(spacing: 0) {
                if cards.isEmpty {
                    EmptyStateView(systemName: "rectangle.on.rectangle", title: "本轮已经看完", message: emptyStateMessage)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    // The paper owns the entire page body. Keeping the deck in a
                    // GeometryReader makes its bottom edge follow the space above
                    // the shared TabView instead of leaving a second blank module
                    // for the card action.
                    GeometryReader { proxy in
                        let currentCard = cards[min(index, cards.count - 1)]
                        let deckHeight = V02CardPreviewLayoutPolicy.previewPageHeight(
                            for: proxy.size.height,
                            entry: currentCard
                        )
                        V02CardDeck(
                            cards: cards,
                            index: $index,
                            height: deckHeight,
                            tuckPrompt: { _ in "收起" }
                        ) { card in
                            cardContent(card)
                        } onTuck: { card in
                            switch card {
                            case .inspiration(let inspiration):
                                do { try store.tuckAway(inspiration.id); undoTuckedInspiration = inspiration }
                                catch { reportError(error) }
                            }
                        }
                        .frame(maxHeight: .infinity, alignment: .top)
                        .padding(.top, V02PrimaryContentLayoutPolicy.topSpacing)
                        .accessibilityHidden(editingInspiration != nil)
                        .overlay(alignment: .bottom) {
                            VStack(spacing: 5) {
                                if cards.indices.contains(index) {
                                    V02AssignCollectionButton {
                                        beginGroupPicker(for: cards)
                                    }
                                }
                                Text("第 \(min(index + 1, cards.count)) / \(cards.count)")
                                    .noteFontCapped(size: 13, maximumScale: 1.25, relativeTo: .caption)
                                    .foregroundStyle(NoteTheme.secondaryInk)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(NoteTheme.ink.opacity(0.045), in: Capsule())
                            }
                            // Keep the action readable above the TabView while
                            // still making it part of the paper, not a separate
                            // floating module below it.
                            .padding(.bottom, 14)
                            .animation(NoteMotion.reveal(reduceMotion: reduceMotion), value: isShowingCollectionPicker)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        // The full-screen editor is presented by this page's navigation
        // stack. Hide the entire card surface, including its floating group
        // action, while the editor owns focus.
        .accessibilityHidden(editingInspiration != nil || localOverlayPresented)
        .onAppear { restoreCardPosition(in: cards) }
        .onChange(of: cards.map(\.id)) { _, _ in restoreCardPosition(in: cards) }
        .onChange(of: index) { _, newIndex in
            guard cards.indices.contains(newIndex) else { return }
            persistedCardID = cards[newIndex].id.uuidString
        }
        .onChange(of: localOverlayPresented) { _, presented in
            onOverlayChange(presented)
        }
        .onDisappear { onOverlayChange(false) }
        .fullScreenCover(item: $editingInspiration, onDismiss: { onEditingChange(false) }) { inspiration in
            V02InspirationEditorView(store: store, inspirationID: inspiration.id, reportError: reportError)
        }
        .background {
            V02PresentedContentAccessibilityIsolation(isPresented: isShowingCollectionPicker)
                .frame(width: 0, height: 0)
        }
        .fullScreenCover(isPresented: $isShowingCollectionPicker) {
            V02ExistingCollectionPicker(
                collections: store.activeCollections,
                memberCount: memberCount(for:),
                onCreate: {
                    isShowingCollectionPicker = false
                    newCollectionName = ""
                    isShowingCreateCollection = true
                },
                onSelect: { collection in
                    assignPendingInspiration(to: collection.id)
                },
                onDismiss: { isShowingCollectionPicker = false }
            )
            .presentationBackground(.clear)
            .interactiveDismissDisabled()
        }
        .alert("新建构思集", isPresented: $isShowingCreateCollection) {
            TextField("构思集名称", text: $newCollectionName)
            Button("创建并归入") { createAndAssignPendingInspiration() }
            Button("取消", role: .cancel) { }
        } message: {
            Text("为当前灵感新建一个构思集。")
        }
        // Keep the undo affordance in the page content area. The native
        // TabView owns the navigation surface; an anchored overlay preserves
        // its hit targets and leaves the card flow usable underneath.
        .overlay(alignment: .bottom) {
            undoBannerContent
                .padding(.horizontal, 16)
                // The shell's four-item navigation occupies roughly 76pt at
                // the bottom. Keep the banner above that stable hit region so
                // its action cannot be mistaken for a tab tap.
                .padding(.bottom, V02NavigationLayoutPolicy.transientBannerBottomPadding)
        }
        .background(NoteTheme.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .notePrimaryHeader {
            if editingInspiration == nil {
                V02PrimaryPageHeader(
                    showTrash: showTrash,
                    showSettings: showSettings,
                    showHistory: showHistory,
                    showSearch: showSearch
                ) {
                    V02PrimaryHeaderTitle()
                }
                .accessibilityHidden(localOverlayPresented)
            }
        }
        }
        .accessibilityHidden(editingInspiration != nil)
        .background(NoteTheme.canvas.ignoresSafeArea())
    }

    @ViewBuilder
    private var undoBannerContent: some View {
        if let undoTuckedInspiration {
            HStack(spacing: 12) {
                Text("已收起")
                    .allowsHitTesting(false)
                Spacer(minLength: 8)
                    .allowsHitTesting(false)
                Button("撤回") {
                    do { try store.returnToCardFlow(undoTuckedInspiration.id) }
                    catch { reportError(error) }
                    self.undoTuckedInspiration = nil
                }
                .buttonStyle(PressScaleButtonStyle())
                .padding(.horizontal, 15)
                .frame(minHeight: 38)
                .foregroundStyle(NoteTheme.ink)
                .noteGlass(cornerRadius: 20, castsShadow: false)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(NoteTheme.paper.opacity(0.82))
                    .overlay { RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.74), lineWidth: 1) }
                    .allowsHitTesting(false)
            }
            .fixedSize(horizontal: false, vertical: true)
            .task(id: undoTuckedInspiration.id) {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                self.undoTuckedInspiration = nil
            }
        }
    }

    private var localOverlayPresented: Bool {
        isShowingCollectionPicker || isShowingCreateCollection
    }

    private func beginGroupPicker(for cards: [V02CardPreviewEntry]) {
        guard cards.indices.contains(index), case .inspiration(let inspiration) = cards[index] else { return }
        pendingInspirationID = inspiration.id
        isShowingCollectionPicker = true
    }

    private func assignPendingInspiration(to collectionID: UUID) {
        guard let inspirationID = pendingInspirationID else {
            isShowingCollectionPicker = false
            return
        }
        do {
            try store.assign(inspirationID, to: collectionID)
            pendingInspirationID = nil
            isShowingCollectionPicker = false
        } catch {
            reportError(error)
        }
    }

    private func createAndAssignPendingInspiration() {
        guard let inspirationID = pendingInspirationID else { return }
        do {
            let trimmed = newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines)
            _ = try store.createCollectionAndRoundAndAssign(
                inspirationID: inspirationID,
                name: trimmed.isEmpty ? nil : trimmed
            )
            pendingInspirationID = nil
        } catch {
            reportError(error)
        }
    }

    private func memberCount(for collection: V02ThinkingCollection) -> Int {
        guard let roundID = collection.currentRoundID,
              let round = store.state.rounds.first(where: { $0.id == roundID }) else { return 0 }
        return round.memberIDs.count
    }

    private func restoreCardPosition(in cards: [V02CardPreviewEntry]) {
        let ids = cards.map(\.id)
        guard let resolved = V02CardPositionPolicy.resolvedIndex(
            preferredID: UUID(uuidString: persistedCardID), currentIndex: index, ids: ids
        ) else { index = 0; persistedCardID = ""; return }
        index = resolved
        persistedCardID = ids[resolved].uuidString
    }

    private func attachmentSummary(for inspiration: V02Inspiration) -> String? {
        guard !inspiration.resourceIDs.isEmpty else { return nil }
        var imageCount = 0
        var audioCount = 0
        var fileCount = 0
        for resourceID in inspiration.resourceIDs {
            guard let resource = store.state.resources.first(where: { $0.id == resourceID }) else { continue }
            if resource.mimeType.hasPrefix("image/") {
                imageCount += 1
            } else if resource.mimeType.hasPrefix("audio/") || resource.source == .voiceInspiration {
                audioCount += 1
            } else {
                fileCount += 1
            }
        }
        let parts = [
            imageCount > 0 ? "图片 \(imageCount)" : nil,
            audioCount > 0 ? "音频 \(audioCount)" : nil,
            fileCount > 0 ? "文件 \(fileCount)" : nil
        ].compactMap { $0 }
        return parts.isEmpty ? "附件 \(inspiration.resourceIDs.count) 个" : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func cardContent(_ card: V02CardPreviewEntry) -> some View {
        switch card {
        case .inspiration(let inspiration):
            VStack(alignment: .leading, spacing: 12) {
                Text(NoteDateFormatter.display(inspiration.createdAt))
                    .noteFont(size: 12, relativeTo: .caption)
                    .foregroundStyle(NoteTheme.secondaryInk)
                Button {
                    editingInspiration = inspiration
                    onEditingChange(true)
                } label: {
                    Text(inspiration.text.isEmpty ? "未命名灵感" : inspiration.text)
                        .noteFont(size: 16, relativeTo: .body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                        .lineLimit(7)
                }
                .buttonStyle(.plain)
                .accessibilityHint("点按编辑这条灵感")
                if let attachmentSummary = attachmentSummary(for: inspiration) {
                    Label(attachmentSummary, systemImage: "paperclip")
                        .noteFont(size: 12, relativeTo: .caption)
                        .foregroundStyle(NoteTheme.secondaryInk)
                }
            }
        }
    }
}
private struct V02AssignCollectionButton: View {
    let action: () -> Void

    var body: some View {
        Button("归入构思集", systemImage: "folder.badge.plus", action: action)
            .noteFontCapped(size: 15, maximumScale: 1.25, weight: .medium, relativeTo: .body)
            .foregroundStyle(NoteTheme.ink)
            .padding(.horizontal, 18)
            .frame(minHeight: 46)
            .noteGlass(cornerRadius: 23, castsShadow: false)
            .buttonStyle(RoundGlassPressButtonStyle())
            .accessibilityHint("打开构思集选择面板")
        }
}

private struct V02ExistingCollectionPicker: View {
    let collections: [V02ThinkingCollection]
    let memberCount: (V02ThinkingCollection) -> Int
    let onCreate: () -> Void
    let onSelect: (V02ThinkingCollection) -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.08)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("归入构思集")
                        .noteFont(size: 19, weight: .semibold, relativeTo: .headline)
                    Spacer()
                    Button("取消", action: onDismiss)
                        .buttonStyle(PressScaleButtonStyle())
                }
                Button("新建构思集", systemImage: "folder.badge.plus", action: onCreate)
                    .noteFont(size: 15, weight: .medium, relativeTo: .body)
                    .foregroundStyle(NoteTheme.ink)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .noteGlass(cornerRadius: 18, castsShadow: false)
                    .buttonStyle(RoundGlassPressButtonStyle())
                ScrollView {
                    LazyVStack(spacing: 10) {
                ForEach(collections) { collection in
                    let count = memberCount(collection)
                    Button {
                        onSelect(collection)
                    } label: {
                        HStack {
                            Image(systemName: "folder.fill")
                            Text(collection.name).lineLimit(1)
                            Spacer()
                            Text("\(count) 条灵感")
                                .foregroundStyle(NoteTheme.secondaryInk)
                        }
                        .noteFont(size: 14, weight: .medium, relativeTo: .body)
                        .foregroundStyle(NoteTheme.ink)
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(RoundGlassPressButtonStyle())
                    .accessibilityLabel("归入 \(collection.name)，当前 \(count) 条灵感")
                    .accessibilityHint("点按将当前灵感归入此构思集")
                }
                if collections.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "folder")
                            .font(.system(size: 24, weight: .medium))
                        Text("当前没有构思中的构思集")
                            .noteFont(size: 15, weight: .medium, relativeTo: .body)
                        Text("新建构思集后，当前灵感会成为第一条成员。")
                            .noteFont(size: 13, relativeTo: .caption)
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(NoteTheme.secondaryInk)
                    .frame(maxWidth: .infinity, minHeight: 112)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("v02.collection-picker.empty")
                }
                    }
                }
                .scrollIndicators(.hidden)
                .frame(maxHeight: 300)
            }
            .padding(22)
            .background(NoteTheme.background, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.white.opacity(0.8), lineWidth: 1) }
            .padding(.horizontal, 14)
            .padding(.bottom, NoteTheme.navigationHeight + 12)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("v02.collection-picker")
    }
}
