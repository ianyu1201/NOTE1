import SwiftUI
import UIKit

struct V02CardPreviewView: View {
    @ObservedObject var store: V02Store
    let onBack: () -> Void
    let onHistory: () -> Void
    let showGeneration: (V02Receipt) -> Void
    let reportError: (Error) -> Void
    let onEditingChange: (Bool) -> Void
    let onOverlayChange: (Bool) -> Void
    @State private var index = 0
    @AppStorage("v02.cardPreview.currentID") private var persistedCardID = ""
    @State private var endingRound: V02ThinkingRound?
    @State private var undoReceipt: V02Receipt?
    @State private var undoTuckedInspiration: V02Inspiration?
    @State private var editingInspiration: V02Inspiration?
    @State private var isShowingGroupTray = false
    @State private var groupTargetFrames = [String: CGRect]()
    @State private var groupButtonFrame = CGRect.zero
    @State private var activeGroupTargetID: String?
    @State private var isDraggingGroup = false
    @State private var isShowingCollectionPicker = false
    @State private var isShowingCreateCollection = false
    @State private var pendingInspirationID: UUID?
    @State private var newCollectionName = ""
    @State private var capacityError: String?

    var body: some View {
        NavigationStack {
        let cards = store.cardPreviewEntries
        ZStack(alignment: .top) {
            NoteTheme.background.ignoresSafeArea()
            VStack(spacing: 10) {
                if cards.isEmpty {
                    EmptyStateView(systemName: "rectangle.on.rectangle", title: "本轮已经看完", message: "收起的灵感仍可在“灵感”中找到。")
                } else {
                V02CardDeck(
                    cards: cards,
                    index: $index,
                    height: 360,
                    tuckPrompt: { card in
                        switch card {
                        case .inspiration: "收起"
                        case .collection: "结束本轮构思"
                        }
                    }
                ) { card in
                    cardContent(card)
                } onTuck: { card in
                    switch card {
                    case .inspiration(let inspiration):
                        do { try store.tuckAway(inspiration.id); undoTuckedInspiration = inspiration }
                        catch { reportError(error) }
                    case .collection(let collection, _):
                        if let roundID = collection.currentRoundID,
                           let round = store.state.rounds.first(where: { $0.id == roundID }) {
                            endingRound = round
                        }
                    }
                }
                .padding(.horizontal, 2)

                // Keep a measured operation gap below the paper. A flexible
                // Spacer here expands to the whole remaining viewport and
                // recreates the empty band this screen is meant to avoid.
                Color.clear
                    .frame(height: 64)
                VStack(spacing: 6) {
                    Group {
                        if cards.indices.contains(index), case .inspiration = cards[index] {
                            V02GroupEntryButton(action: {
                                beginGroupPicker(for: cards)
                            }, onDrag: { location, translation, ended in
                                if translation.height < -18 {
                                    isShowingGroupTray = true
                                    isDraggingGroup = true
                                }
                                // V02GroupEntryButton reports its drag in the same global
                                // coordinate space as the tray frames, so the final
                                // location is compared directly without frame-offset
                                // guesses that drift when the overlay reflows.
                                let point = location
                                activeGroupTargetID = V02GroupTargetPolicy.activeTarget(at: point, frames: groupTargetFrames)
                                if ended {
                                    let finalTarget = V02GroupTargetPolicy.activeTarget(at: point, frames: groupTargetFrames)
                                    defer { activeGroupTargetID = nil; isShowingGroupTray = false; isDraggingGroup = false }
                                    guard translation.height < -50,
                                          case .inspiration(let inspiration) = cards[min(index, cards.count - 1)],
                                          let target = V02GroupTargetPolicy.commitTarget(finalActiveTarget: finalTarget) else { return }
                                    pendingInspirationID = inspiration.id
                                    handleGroupOperation(target)
                                }
                            })
                        } else {
                            Color.clear
                                .frame(width: 52, height: 52)
                                .accessibilityHidden(true)
                        }
                    }
                    .background(GeometryReader { proxy in
                        Color.clear.preference(key: GroupButtonFrameKey.self, value: proxy.frame(in: .named("cardPreview")))
                    })
                    // Keep the source control above the page-local dismiss layer. This
                    // preserves outside-tap dismissal while allowing a second gesture
                    // to begin from the same fixed button after the tray is open.
                    .zIndex(isShowingGroupTray ? 6 : 0)
                    .accessibilityHint("点按或按住上拖，打开构思集选择托盘")
                    Text("第 \(min(index + 1, cards.count)) / \(cards.count)")
                        .noteFontCapped(size: 13, maximumScale: 1.25, relativeTo: .caption)
                        .foregroundStyle(NoteTheme.secondaryInk)
                }
                .padding(.bottom, 8)
                }
            }
            // The tab bar already owns the system safe-area boundary. Keep a
            // small optical gap here rather than reserving a second full bar
            // height, which would recreate the empty band this page is meant
            // to avoid.
            .padding(.bottom, 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.bottom, 22)
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
        .alert("结束本轮构思？", isPresented: Binding(
            get: { endingRound != nil }, set: { if !$0 { endingRound = nil } }
        ), presenting: endingRound) { round in
            Button("结束并生成小票") {
                finishRound(round)
            }
            Button("取消", role: .cancel) { endingRound = nil }
        } message: { _ in
            Text("确认后会为这一轮构思生成一张固定小票。")
        }
        .fullScreenCover(item: $editingInspiration, onDismiss: { onEditingChange(false) }) { inspiration in
            V02InspirationEditorView(store: store, inspirationID: inspiration.id, reportError: reportError)
        }
        .coordinateSpace(name: "cardPreview")
        .simultaneousGesture(
            SpatialTapGesture().onEnded { value in
                guard isShowingGroupTray, !isDraggingGroup else { return }
                let point = value.location
                let isInsideButton = groupButtonFrame.contains(point)
                let isInsideTarget = groupTargetFrames.values.contains { $0.contains(point) }
                guard !isInsideButton, !isInsideTarget else { return }
                activeGroupTargetID = nil
                isShowingGroupTray = false
            }
        )
        .onPreferenceChange(GroupButtonFrameKey.self) {
            groupButtonFrame = $0
        }
        .overlay {
            if isShowingGroupTray {
                GeometryReader { proxy in
                    V02GroupPickerTray(
                        collections: store.activeCollections,
                        mode: .actions,
                        targetFrames: $groupTargetFrames,
                        activeTargetID: activeGroupTargetID,
                        onSelect: { handleGroupOperation("existing") },
                        onCreate: { handleGroupOperation("new") }
                    )
                    .frame(width: min(350, proxy.size.width - 24))
                    .position(
                        x: proxy.size.width / 2,
                        // Anchor the expansion to the measured source button.
                        // A page-height offset can put the tray below the
                        // viewport on tall devices; the source frame keeps it
                        // directly above the button on every size.
                        y: max(120, groupButtonFrame.minY - 48)
                    )
                }
                .allowsHitTesting(!isDraggingGroup)
                .transition(.opacity)
            }
        }
        .overlay {
            if isShowingCollectionPicker {
                V02ExistingCollectionPicker(
                    collections: store.activeCollections,
                    memberCount: memberCount(for:),
                    onSelect: { collection in
                        assignPendingInspiration(to: collection.id)
                    },
                    onDismiss: { isShowingCollectionPicker = false }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(4)
            }
        }
        .alert("新建构思集", isPresented: $isShowingCreateCollection) {
            TextField("构思集名称", text: $newCollectionName)
            Button("创建并归入") { createAndAssignPendingInspiration() }
            Button("取消", role: .cancel) { }
        } message: {
            Text("为当前灵感新建一个构思集。")
        }
        .alert("暂时无法归入", isPresented: Binding(
            get: { capacityError != nil },
            set: { if !$0 { capacityError = nil } }
        )) {
            Button("知道了", role: .cancel) { capacityError = nil }
        } message: {
            Text(capacityError ?? "")
        }
        // Keep the undo affordance in the page content area. The app shell
        // owns the bottom navigation safe-area inset; nesting another inset
        // here can place the button below the visible viewport and let the
        // navigation hit targets win. An anchored overlay preserves the
        // navigation bar and leaves the card flow usable underneath.
        .overlay(alignment: .bottom) {
            undoBannerContent
                .padding(.horizontal, 16)
                // The shell's four-item navigation occupies roughly 76pt at
                // the bottom. Keep the banner above that stable hit region so
                // its action cannot be mistaken for a tab tap.
                .padding(.bottom, 152)
        }
        .background(NoteTheme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .fontWeight(.semibold)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("返回灵感")
            }
            ToolbarItem(placement: .principal) {
                Text("NOTE1")
                    .noteFontCapped(
                        size: 20,
                        maximumScale: 1.2,
                        weight: .medium,
                        design: .rounded,
                        relativeTo: .headline
                    )
                    .tracking(6)
                    .foregroundStyle(NoteTheme.ink)
                    .accessibilityAddTraits(.isHeader)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onHistory) {
                    Image(systemName: "clock.arrow.circlepath")
                        .fontWeight(.semibold)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("历史记录")
            }
        }
        }
        .background(NoteTheme.background.ignoresSafeArea())
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
        } else if let undoReceipt {
            HStack(spacing: 12) {
                Text("本轮构思已结束，\(undoReceipt.snapshot.members.count) 条灵感已收录。")
                    .lineLimit(2)
                    .allowsHitTesting(false)
                Spacer(minLength: 8)
                    .allowsHitTesting(false)
                Button("撤回") {
                    do { try store.undoEndRound(undoReceipt.id) }
                    catch { reportError(error) }
                    self.undoReceipt = nil
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
            .task(id: undoReceipt.id) {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                self.undoReceipt = nil
            }
        }
    }

    private func handleGroupOperation(_ target: String) {
        isShowingGroupTray = false
        activeGroupTargetID = nil
        isDraggingGroup = false
        switch target {
        case "new":
            newCollectionName = ""
            isShowingCreateCollection = true
        case "existing":
            isShowingCollectionPicker = true
        default:
            break
        }
    }

    private var localOverlayPresented: Bool {
        isShowingGroupTray || isShowingCollectionPicker || isShowingCreateCollection || endingRound != nil || capacityError != nil
    }

    private func beginGroupPicker(for cards: [V02CardPreviewEntry]) {
        guard cards.indices.contains(index), case .inspiration(let inspiration) = cards[index] else { return }
        pendingInspirationID = inspiration.id
        isShowingGroupTray = true
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
        } catch NoteStoreError.invalidOperation(_) {
            capacityError = "当前版本每个构思集只支持 10 条灵感"
        } catch V02DomainError.collectionCapacity {
            capacityError = "当前版本每个构思集只支持 10 条灵感"
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

    private func finishRound(_ round: V02ThinkingRound) {
        do {
            showGeneration(try store.endRound(round.id))
            endingRound = nil
        } catch { reportError(error) }
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
                Spacer(minLength: 26)
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
                Spacer(minLength: 26)
            }
        case .collection(let collection, let memberCount):
            VStack(alignment: .leading, spacing: 14) {
                Label("构思集", systemImage: "folder.fill")
                    .noteFont(size: 15, weight: .semibold, relativeTo: .headline)
                    .foregroundStyle(NoteTheme.secondaryInk)
                Text(collection.name)
                    .noteFont(size: 22, weight: .semibold, relativeTo: .title2)
                Text("本轮含 \(memberCount) 条灵感。可在“构思集”继续调整顺序与内容。")
                    .noteFont(size: 16, relativeTo: .body)
                    .foregroundStyle(NoteTheme.secondaryInk)
            }
        }
    }
}
private struct V02GroupEntryButton: View {
    let action: () -> Void
    var onDrag: (CGPoint, CGSize, Bool) -> Void = { _, _, _ in }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: "square.stack.3d.up.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(NoteTheme.ink)
                    .frame(width: 52, height: 52)
                    .background(Color.white.opacity(0.72), in: Circle())
                    .overlay { Circle().stroke(Color.white.opacity(0.9), lineWidth: 1) }
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(NoteTheme.ink, in: Circle())
                    .offset(x: 4, y: -3)
        }
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { value in
                    guard abs(value.translation.height) >= 10 || abs(value.translation.width) >= 10 else { return }
                    onDrag(value.location, value.translation, false)
                }
                .onEnded { value in
                    let distance = hypot(value.translation.width, value.translation.height)
                    if distance < 10 {
                        action()
                    } else {
                        onDrag(value.location, value.translation, true)
                    }
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("归入构思集")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
    }
}

private struct V02GroupPickerTray: View {
    enum Mode {
        case actions
        case existing
    }

    let collections: [V02ThinkingCollection]
    let mode: Mode
    @Binding var targetFrames: [String: CGRect]
    let activeTargetID: String?
    let onSelect: () -> Void
    let onCreate: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if mode == .actions {
                let targetIDs = V02GroupOperationPolicy.targetIDs(activeCollectionCount: collections.count)
                HStack(alignment: .center, spacing: 14) {
                    if targetIDs.contains("new") {
                        actionTarget(
                            id: "new",
                            systemName: "folder.badge.plus",
                            title: "新建构思集",
                            action: onCreate
                        )
                        .rotationEffect(.degrees(-4))
                    }
                    if targetIDs.contains("existing") {
                        actionTarget(
                            id: "existing",
                            systemName: "folder.fill",
                            title: "归入现有构思集",
                            action: onSelect
                        )
                        .rotationEffect(.degrees(4))
                    }
                }
                .frame(maxWidth: .infinity)
            }
            /*
             The concrete list is intentionally a second interaction after the
             operation target is chosen. Keeping the drag tray to two stable
             operation targets prevents a finger from having to aim at a tiny
             collection row while the card is moving.
             */
            if mode == .existing {
                LazyVGrid(columns: [GridItem(.flexible())], spacing: 10) {
                    ForEach(collections.prefix(5)) { collection in
                        Button {
                            onSelect()
                        } label: {
                            HStack {
                                Image(systemName: "folder.fill")
                                Text(collection.name).lineLimit(1)
                                Spacer()
                                Text(V02GroupOperationPolicy.capacityLabel(memberCount: memberCount(for: collection)))
                                    .foregroundStyle(NoteTheme.secondaryInk)
                            }
                            .noteFont(size: 13, weight: .medium, relativeTo: .caption)
                            .foregroundStyle(NoteTheme.ink)
                            .padding(.horizontal, 14)
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .background(Color.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(RoundGlassPressButtonStyle())
                        .opacity(V02GroupOperationPolicy.canAccept(memberCount: memberCount(for: collection)) ? 1 : 0.54)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .onPreferenceChange(GroupTargetFramesKey.self) {
            targetFrames = $0
        }
    }

    private func actionTarget(
        id: String,
        systemName: String,
        title: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: systemName)
                Text(title)
            }
            .noteFont(size: 13, weight: .medium, relativeTo: .caption)
            .foregroundStyle(NoteTheme.ink)
            .padding(.horizontal, 12)
            .frame(minWidth: 142, minHeight: 60)
            .background(
                activeTargetID == id ? NoteTheme.ink.opacity(0.16) : Color.white.opacity(0.72),
                in: Capsule()
            )
        }
        .buttonStyle(RoundGlassPressButtonStyle())
        .accessibilityLabel(title)
        .background(GeometryReader { proxy in
            let visibleFrame = proxy.frame(in: .global)
            // Keep the visual capsules side-by-side, but give the physical
            // target a forgiving transparent halo for a straight upward drag.
            // The halo is the frame used by the state machine; it does not
            // change the confirmed visual relationship.
            let hitFrame = visibleFrame.insetBy(dx: -8, dy: -14)
            return Color.clear.preference(key: GroupTargetFramesKey.self, value: [id: hitFrame])
        })
    }

    private func memberCount(for collection: V02ThinkingCollection) -> Int {
        collection.currentRoundID.flatMap { roundID in
            // The operation tray only needs a compact count; this path is replaced by
            // the card preview's live collection picker when a concrete target is tapped.
            _ = roundID
            return nil
        } ?? 0
    }
}

private struct V02ExistingCollectionPicker: View {
    let collections: [V02ThinkingCollection]
    let memberCount: (V02ThinkingCollection) -> Int
    let onSelect: (V02ThinkingCollection) -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.001)
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("归入现有构思集")
                        .noteFont(size: 19, weight: .semibold, relativeTo: .headline)
                    Spacer()
                    Button("取消", action: onDismiss)
                        .buttonStyle(PressScaleButtonStyle())
                }
                ForEach(collections.prefix(5)) { collection in
                    let count = memberCount(collection)
                    Button {
                            onSelect(collection)
                    } label: {
                        HStack {
                            Image(systemName: "folder.fill")
                            Text(collection.name).lineLimit(1)
                            Spacer()
                            Text(V02GroupOperationPolicy.capacityLabel(memberCount: count))
                                .foregroundStyle(NoteTheme.secondaryInk)
                        }
                        .noteFont(size: 14, weight: .medium, relativeTo: .body)
                        .foregroundStyle(NoteTheme.ink)
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(RoundGlassPressButtonStyle())
                    .opacity(count >= 10 ? 0.54 : 1)
                    .accessibilityLabel("归入 \(collection.name)，当前 \(count) 条，共 10 条")
                }
                if collections.isEmpty {
                    Text("当前没有构思中的构思集")
                        .noteFont(size: 14, relativeTo: .body)
                        .foregroundStyle(NoteTheme.secondaryInk)
                }
            }
            .padding(22)
            .background(NoteTheme.background, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Color.white.opacity(0.8), lineWidth: 1) }
            .padding(.horizontal, 14)
            .padding(.bottom, NoteTheme.navigationHeight + 12)
        }
        .accessibilityElement(children: .contain)
    }
}
