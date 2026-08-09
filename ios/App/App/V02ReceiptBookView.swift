import SwiftUI

struct V02ReceiptBookView: View {
    @ObservedObject var store: V02Store
    @Binding var isSelecting: Bool
    let showSettings: () -> Void
    let showTrash: () -> Void
    let showHistory: () -> Void
    let showSearch: () -> Void
    let onOverlayChange: (Bool) -> Void
    @State private var selectedIDs = Set<UUID>()
    @State private var pendingDeleteIDs = Set<UUID>()
    @State private var shareURLs: [URL] = []
    @State private var error: UserFacingAlert?
    @State private var receiptIndex = 0
    @State private var detailReceipt: V02Receipt?
    @State private var undoTrashEntryIDs = Set<UUID>()
    @State private var templateOverrides: [UUID: V02ReceiptTemplate] = [:]
    @State private var receiptTranslation: CGSize = .zero
    @State private var receiptGestureAxis: V02ReceiptGestureAxis = .none
    @State private var receiptGestureStartedAtEdge = false
    @State private var receiptGestureStartedAtExtractionHandle = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .body) private var receiptTextScale: CGFloat = 1

    private var selectedReceipts: [V02Receipt] {
        store.state.receipts.filter { selectedIDs.contains($0.id) }
    }

    private var receipts: [V02Receipt] {
        store.state.receipts.sorted { $0.createdAt > $1.createdAt }
    }

    private var currentReceipt: V02Receipt? {
        guard receipts.indices.contains(receiptIndex) else { return nil }
        return receipts[receiptIndex]
    }

    private var localOverlayPresented: Bool {
        detailReceipt != nil || !shareURLs.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if isSelecting { selectionToolbar }
                    if receipts.isEmpty {
                        emptyBook
                    } else {
                        V02ReceiptDeck(
                            store: store,
                            receipts: receipts,
                            index: $receiptIndex,
                            isSelecting: isSelecting,
                            selectedIDs: $selectedIDs,
                            openReceipt: { detailReceipt = $0 },
                            minimumPaperHeight: currentReceipt.map(receiptPaperHeight)
                                ?? V02ReceiptLayoutPolicy.minimumPaperHeight,
                            templateFor: { receipt in
                                templateOverrides[receipt.id]
                                    ?? V02ReceiptTemplate.recommended(for: receipt, resources: store.state.resources)
                            },
                            translation: receiptTranslation,
                            axis: receiptGestureAxis
                        )
                        .zIndex(1)
                        Text("第 \(receiptIndex + 1) 张，共 \(receipts.count) 张")
                            .noteFontCapped(
                                size: 13,
                                maximumScale: V02PrimaryTypographyPolicy.contextLabelMaximumScale,
                                relativeTo: .caption
                            )
                            .foregroundStyle(NoteTheme.secondaryInk)
                            .monospacedDigit()
                            .lineLimit(1)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background(NoteTheme.ink.opacity(0.045), in: Capsule())
                            .accessibilityLabel("第 \(receiptIndex + 1) 张，共 \(receipts.count) 张。可左右切换或向下抽取。")
                            .padding(.top, 18)
                    }
                }
                .padding(.horizontal, V02PrimaryContentLayoutPolicy.horizontalInset)
                .padding(.top, V02PrimaryContentLayoutPolicy.topSpacing)
            }
            .scrollIndicators(.hidden)
            // Receipt navigation belongs to the same gesture arena as the
            // reading ScrollView. Upward and non-handle vertical drags are
            // therefore left to scrolling, while a locked horizontal drag or
            // explicit top-handle pull drives the paper deck.
            .simultaneousGesture(
                receipts.isEmpty || isSelecting ? nil : receiptNavigationGesture()
            )
            .accessibilityHidden(localOverlayPresented)
            .background(NoteTheme.background.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear
                    .frame(height: V02NavigationLayoutPolicy.primaryContentBottomPadding)
                    .allowsHitTesting(false)
            }
            .toolbar(.hidden, for: .navigationBar)
            .notePrimaryHeader {
                if !localOverlayPresented {
                    receiptHeader
                }
            }
        }
        .onAppear { onOverlayChange(localOverlayPresented) }
        .onChange(of: localOverlayPresented) { _, presented in
            onOverlayChange(presented)
        }
        .onDisappear { onOverlayChange(false) }
        .onChange(of: receipts.map(\.id)) { _, ids in
            receiptIndex = min(receiptIndex, max(0, ids.count - 1))
        }
        .sheet(item: $detailReceipt) { receipt in
            V02ReceiptDetailView(
                store: store,
                receipt: receipt,
                export: export,
                onDelete: { entryIDs in undoTrashEntryIDs.formUnion(entryIDs) }
            )
        }
        .sheet(isPresented: Binding(
            get: { !shareURLs.isEmpty },
            set: { if !$0 { shareURLs.removeAll() } }
        )) {
            NavigationStack {
                List(shareURLs, id: \.self) { url in
                    ShareLink(item: url) { Label(url.lastPathComponent, systemImage: "square.and.arrow.up") }
                }
                .navigationTitle("导出文件")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { shareURLs.removeAll() } } }
            }
        }
        .alert("删除构思小票？", isPresented: Binding(
            get: { !pendingDeleteIDs.isEmpty },
            set: { if !$0 { pendingDeleteIDs.removeAll() } }
        )) {
            Button("删除", role: .destructive) { deleteSelectedReceipts() }
            Button("取消", role: .cancel) { pendingDeleteIDs.removeAll() }
        } message: {
            Text("删除后可在回收站中恢复。")
        }
        .overlay(alignment: .bottom) {
            V02ReceiptUndoTrashBanner(store: store, entryIDs: $undoTrashEntryIDs) { error in
                self.error = UserFacingAlert(error: error)
            }
            .padding(.bottom, V02NavigationLayoutPolicy.transientBannerBottomPadding)
        }
        .noteErrorAlert($error)
    }

    private var receiptHeader: some View {
        V02PrimaryPageHeader(
            showTrash: showTrash,
            showSettings: showSettings,
            showHistory: showHistory,
            showSearch: showSearch
        ) {
            receiptTitleMenu
        }
    }

    private var receiptTitleMenu: some View {
        Menu {
            Button(isSelecting ? "取消选择" : "选择", systemImage: "checkmark.circle") {
                isSelecting.toggle()
                if !isSelecting { selectedIDs.removeAll() }
            }
            Menu("切换模板", systemImage: "rectangle.2.swap") {
                ForEach(V02ReceiptTemplate.allCases) { template in
                    Button(template.rawValue) { setTemplate(template) }
                }
            }
            Button("导出 PDF", systemImage: "doc.badge.arrow.up") { exportCurrent(.pdf) }
            Button("分享", systemImage: "square.and.arrow.up") { exportCurrent(.pdf) }
            Button("复制", systemImage: "doc.on.doc") { copyCurrentReceipt() }
            Button("在小票中查找", systemImage: "magnifyingglass") {
                if let currentReceipt { detailReceipt = currentReceipt }
            }
            Button("删除", systemImage: "trash", role: .destructive) {
                if let currentReceipt { pendingDeleteIDs = [currentReceipt.id] }
            }
        } label: {
            V02PrimaryHeaderTitle(showsMenuIndicator: true)
        }
        .accessibilityLabel("NOTE1，小票更多操作")
    }

    private var selectionToolbar: some View {
        ViewThatFits(in: .horizontal) {
            selectionActions(axis: .horizontal)
                .fixedSize(horizontal: true, vertical: false)
            selectionActions(axis: .vertical)
        }
        .foregroundStyle(NoteTheme.ink)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: 278)
        .noteGlass(cornerRadius: 15, castsShadow: false)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityIdentifier("v02.receipt.selection")
    }

    private enum SelectionActionAxis { case horizontal, vertical }

    @ViewBuilder
    private func selectionActions(axis: SelectionActionAxis) -> some View {
        if axis == .horizontal {
            HStack(spacing: 10) {
                Text("已选 \(selectedIDs.count) 张")
                    .noteFont(size: 14, weight: .medium, relativeTo: .subheadline)
                selectionActionButtons
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("已选 \(selectedIDs.count) 张")
                    .noteFont(size: 14, weight: .medium, relativeTo: .subheadline)
                selectionActionButtons
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var selectionActionButtons: some View {
        Button("全选") { selectedIDs = Set(receipts.map(\.id)) }
            .buttonStyle(.plain)
            .frame(minHeight: 44)
        Menu("操作") {
            Button("导出 PDF", systemImage: "arrow.down.doc") { exportSelectedPDFs() }
                .disabled(selectedIDs.isEmpty)
            Button("分享 PDF", systemImage: "square.and.arrow.up") { exportSelectedPDFs() }
                .disabled(selectedIDs.isEmpty)
            Button("删除", role: .destructive) { pendingDeleteIDs = selectedIDs }
                .disabled(selectedIDs.isEmpty)
        }
        .accessibilityLabel("批量操作")
        .frame(minHeight: 44)
    }

    private var emptyBook: some View {
        VStack(spacing: 18) {
            V02TicketClip().padding(.horizontal, 22)
            VStack(spacing: 10) {
                Text("每一轮构思，都留下一张存根")
                    .noteFont(size: 21, weight: .semibold, design: .rounded, relativeTo: .title3)
                Text("结束一轮构思后，小票会从这里的票据夹中出现。")
                    .noteFont(size: 15, relativeTo: .body)
                    .foregroundStyle(NoteTheme.secondaryInk)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 30)
        }
        .frame(maxWidth: .infinity, minHeight: 430)
        .accessibilityIdentifier("v02.receipt.empty")
    }

    private func export(_ receipt: V02Receipt, format: V02ReceiptExportFormat) {
        do {
            shareURLs = [try V02ReceiptExportFile.write(
                receipt,
                format: format,
                resourceURL: { store.resourceURL(relativePath: $0) }
            )]
        }
        catch { self.error = UserFacingAlert(error: error) }
    }

    private func exportSelectedPDFs() {
        do {
            shareURLs = try V02ReceiptExportFile.writePDFs(
                selectedReceipts,
                resourceURL: { store.resourceURL(relativePath: $0) }
            )
        }
        catch { self.error = UserFacingAlert(error: error) }
    }

    private func deleteSelectedReceipts() {
        do {
            undoTrashEntryIDs.formUnion(try store.batchDeleteReceipts(pendingDeleteIDs))
            selectedIDs.subtract(pendingDeleteIDs)
            pendingDeleteIDs.removeAll()
        } catch {
            self.error = UserFacingAlert(error: error)
        }
    }

    private func receiptPaperHeight(_ receipt: V02Receipt) -> CGFloat {
        let members = receipt.snapshot.members
        let memberCount = CGFloat(max(members.count, 1))
        let estimatedTextLines = CGFloat(members.reduce(0) { partial, member in
            let count = member.text.trimmingCharacters(in: .whitespacesAndNewlines).count
            return partial + max(1, Int(ceil(Double(max(count, 1)) / 18.0)))
        })
        let hasAttachments = !members.flatMap(\.attachments).isEmpty
        let hasPhotoStrip = V02ReceiptTemplate.recommended(
            for: receipt,
            resources: store.state.resources
        ) == .film

        // Reserve one measured line budget rather than counting both a full
        // card row and all of its text twice. The ticket remains long enough
        // for wrapping, while its footer no longer trails a large blank tail.
        return V02ReceiptLayoutPolicy.estimatedPaperHeight(
            memberCount: Int(memberCount),
            textLineCount: Int(estimatedTextLines),
            hasAttachments: hasAttachments,
            hasPhotoStrip: hasPhotoStrip,
            textScale: receiptTextScale
        )
    }

    private func receiptNavigationGesture() -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                let width = max(UIScreen.main.bounds.width, 1)
                let edgeInset = min(32, width * 0.08)
                if value.startLocation.x < edgeInset || value.startLocation.x > width - edgeInset {
                    receiptGestureStartedAtEdge = true
                    return
                }
                guard !receiptGestureStartedAtEdge else { return }

                if receiptGestureAxis == .none {
                    let proposedAxis = V02ReceiptGesturePolicy.axis(for: value.translation)
                    if proposedAxis == .downward {
                        receiptGestureStartedAtExtractionHandle = V02ReceiptGesturePolicy.canStartExtraction(
                            at: value.startLocation
                        )
                        guard receiptGestureStartedAtExtractionHandle else { return }
                    }
                    guard proposedAxis != .none else { return }
                    receiptGestureAxis = proposedAxis
                }

                receiptTranslation = value.translation
            }
            .onEnded { value in
                guard !receiptGestureStartedAtEdge else {
                    resetReceiptGesture()
                    return
                }

                switch receiptGestureAxis {
                case .horizontal:
                    finishHorizontalReceiptGesture(value)
                case .downward:
                    finishExtractionGesture(value)
                case .none:
                    resetReceiptGesture(animated: true)
                }
            }
    }

    private func finishHorizontalReceiptGesture(_ value: DragGesture.Value) {
        guard let target = V02ReceiptGesturePolicy.horizontalTarget(
            index: receiptIndex,
            count: receipts.count,
            translation: value.translation.width
        ) else {
            resetReceiptGesture(animated: true)
            return
        }

        let duration = reduceMotion ? 0.12 : 0.32
        let width = max(UIScreen.main.bounds.width, 1)
        withAnimation(reduceMotion ? .easeOut(duration: duration) : .smooth(duration: duration)) {
            receiptTranslation.width = reduceMotion
                ? (value.translation.width < 0 ? -24 : 24)
                : (value.translation.width < 0 ? -width : width)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.01) {
            receiptIndex = target
            resetReceiptGesture()
        }
    }

    private func finishExtractionGesture(_ value: DragGesture.Value) {
        guard receiptGestureStartedAtExtractionHandle,
              V02ReceiptGesturePolicy.shouldExtract(value.translation.height),
              let currentReceipt else {
            resetReceiptGesture(animated: true)
            return
        }

        let duration = reduceMotion ? 0.16 : 0.28
        let extractionDistance = max(UIScreen.main.bounds.height * 1.25, 1)
        withAnimation(.easeIn(duration: duration)) {
            receiptTranslation.height = extractionDistance
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.02) {
            detailReceipt = currentReceipt
            resetReceiptGesture()
        }
    }

    private func resetReceiptGesture(animated: Bool = false) {
        let changes = {
            receiptTranslation = .zero
            receiptGestureAxis = .none
            receiptGestureStartedAtEdge = false
            receiptGestureStartedAtExtractionHandle = false
        }
        if animated {
            withAnimation(NoteMotion.settle(reduceMotion: reduceMotion), changes)
        } else {
            changes()
        }
    }

    private func setTemplate(_ template: V02ReceiptTemplate) {
        guard let currentReceipt else { return }
        templateOverrides[currentReceipt.id] = template
    }

    private func exportCurrent(_ format: V02ReceiptExportFormat) {
        guard let currentReceipt else { return }
        export(currentReceipt, format: format)
    }

    private func copyCurrentReceipt() {
        guard let currentReceipt else { return }
        let body = currentReceipt.snapshot.members.map(\.text).joined(separator: "\n\n")
        UIPasteboard.general.string = "\(currentReceipt.snapshot.collectionName)\n\n\(body)"
    }
}

private struct V02ReceiptUndoTrashBanner: View {
    @ObservedObject var store: V02Store
    @Binding var entryIDs: Set<UUID>
    let reportError: (Error) -> Void

    var body: some View {
        if !entryIDs.isEmpty {
            HStack {
                Text("已移入回收站")
                Spacer()
                Button("撤回") {
                    do { try store.restoreTrash(entryIDs); entryIDs.removeAll() }
                    catch { reportError(error) }
                }
                .buttonStyle(PressScaleButtonStyle())
                .noteGlass(cornerRadius: 16, castsShadow: false)
            }
            .accessibilityLabel("构思小票已移入回收站，可在两秒内撤回")
            .padding(12)
            .background(NoteTheme.background.opacity(0.92), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, 16)
            .task(id: entryIDs) {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                entryIDs.removeAll()
            }
        }
    }
}
