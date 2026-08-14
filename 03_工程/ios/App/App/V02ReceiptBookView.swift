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
    @State private var detailReceipt: V02Receipt?
    @State private var undoTrashEntryIDs = Set<UUID>()
    @State private var templateOverrides: [UUID: V02ReceiptTemplate] = [:]
    @State private var latestExtractionTranslation: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var selectedReceipts: [V02Receipt] {
        store.state.receipts.filter { selectedIDs.contains($0.id) }
    }

    private var receipts: [V02Receipt] {
        store.state.receipts.sorted { $0.createdAt > $1.createdAt }
    }

    private var currentReceipt: V02Receipt? {
        receipts.first
    }

    private var localOverlayPresented: Bool {
        detailReceipt != nil || !shareURLs.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if isSelecting { selectionToolbar }
                    if receipts.isEmpty {
                        emptyBook
                    } else {
                        if let latest = receipts.first {
                            Text("最新小票")
                                .noteFont(size: 20, weight: .semibold, relativeTo: .title3)
                                .foregroundStyle(NoteTheme.ink)
                                .accessibilityAddTraits(.isHeader)
                            Button {
                                detailReceipt = latest
                            } label: {
                                V02ReceiptPaper(
                                    store: store,
                                    receipt: latest,
                                    template: templateFor(latest),
                                    minimumHeight: 390
                                )
                                .frame(maxWidth: .infinity)
                                .frame(height: 286, alignment: .top)
                                .clipped()
                                .contentShape(Rectangle())
                                .offset(y: latestExtractionTranslation)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("最新小票，\(latest.snapshot.collectionName)，\(latest.statistics.roundTitle)")
                            .accessibilityHint("双击查看完整小票")
                            .accessibilityIdentifier("v04.receipt.latest")
                            .overlay(alignment: .top) {
                                Button {
                                    detailReceipt = latest
                                } label: {
                                    Rectangle()
                                        .fill(Color.clear)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: V02ReceiptGesturePolicy.extractionHandleHeight)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .highPriorityGesture(latestExtractionGesture(for: latest))
                                .accessibilityHidden(true)
                            }
                        }

                        Text("全部小票")
                            .noteFont(size: 20, weight: .semibold, relativeTo: .title3)
                            .foregroundStyle(NoteTheme.ink)
                            .accessibilityAddTraits(.isHeader)
                            .padding(.top, 4)
                        ForEach(receipts) { receipt in
                            receiptIndexRow(receipt)
                        }
                    }
                }
                .padding(.horizontal, V02PrimaryContentLayoutPolicy.horizontalInset)
                .padding(.top, V02PrimaryContentLayoutPolicy.topSpacing)
            }
            .scrollIndicators(.hidden)
            .accessibilityHidden(localOverlayPresented)
            .background(NoteTheme.canvas.ignoresSafeArea())
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
        .fullScreenCover(item: $detailReceipt) { receipt in
            V04ReceiptReaderView(
                store: store,
                receipts: receipts,
                initialReceiptID: receipt.id,
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
        ContentUnavailableView(
            "还没有构思小票",
            systemImage: V04ReceiptSymbolPolicy.emptyStateSymbol,
            description: Text("结束一轮构思并生成小票后，会在这里看到最新小票和全部索引。")
        )
        .frame(maxWidth: .infinity, minHeight: 430)
        .accessibilityIdentifier("v02.receipt.empty")
    }

    private func receiptIndexRow(_ receipt: V02Receipt) -> some View {
        Button {
            if isSelecting {
                if selectedIDs.contains(receipt.id) {
                    selectedIDs.remove(receipt.id)
                } else {
                    selectedIDs.insert(receipt.id)
                }
            } else {
                detailReceipt = receipt
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: isSelecting
                    ? (selectedIDs.contains(receipt.id) ? "checkmark.circle.fill" : "circle")
                    : V04ReceiptSymbolPolicy.objectIndexSymbol)
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(NoteTheme.ink)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 5) {
                    Text(receipt.snapshot.collectionName)
                        .noteFont(size: 16, weight: .semibold, relativeTo: .headline)
                        .foregroundStyle(NoteTheme.ink)
                        .lineLimit(1)
                    Text("\(receipt.statistics.roundTitle) · \(receipt.snapshot.members.count) 条灵感 · \(receipt.createdAt.formatted(date: .abbreviated, time: .shortened))")
                        .noteFont(size: 13, relativeTo: .subheadline)
                        .foregroundStyle(NoteTheme.secondaryInk)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                if !isSelecting {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(NoteTheme.secondaryInk)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .overlay(alignment: .bottom) {
                Rectangle().fill(NoteTheme.divider).frame(height: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(receipt.snapshot.collectionName)，\(receipt.statistics.roundTitle)，\(receipt.snapshot.members.count) 条灵感")
        .accessibilityHint(isSelecting ? "双击切换选择" : "双击查看完整小票")
    }

    private func latestExtractionGesture(for receipt: V02Receipt) -> some Gesture {
        DragGesture(
            minimumDistance: V02ReceiptGesturePolicy.lockDistance,
            coordinateSpace: .local
        )
        .onChanged { value in
            guard V02ReceiptGesturePolicy.canStartExtraction(at: value.startLocation),
                  value.translation.height > 0,
                  V02ReceiptGesturePolicy.axis(for: value.translation) == .downward else {
                latestExtractionTranslation = 0
                return
            }

            // Keep the latest preview connected to the pull while retaining a
            // little resistance so a long drag does not throw the root page
            // out of place.
            let extractionScale: CGFloat = reduceMotion ? 0.24 : 0.68
            let extractionLimit: CGFloat = reduceMotion ? 16 : 128
            latestExtractionTranslation = min(value.translation.height * extractionScale, extractionLimit)
        }
        .onEnded { value in
            let startsAtHandle = V02ReceiptGesturePolicy.canStartExtraction(at: value.startLocation)
            let isDownward = V02ReceiptGesturePolicy.axis(for: value.translation) == .downward
            let extracts = startsAtHandle
                && isDownward
                && V02ReceiptGesturePolicy.shouldExtract(
                    value.translation.height,
                    predictedEndTranslation: value.predictedEndTranslation.height
                )

            if extracts {
                // The full-screen reader owns the receipt after this point;
                // reset the preview before presenting it so a cancelled
                // presentation cannot leave a displaced root page behind.
                latestExtractionTranslation = 0
                detailReceipt = receipt
            } else {
                withAnimation(NoteMotion.settle(reduceMotion: reduceMotion)) {
                    latestExtractionTranslation = 0
                }
            }
        }
    }

    private func templateFor(_ receipt: V02Receipt) -> V02ReceiptTemplate {
        templateOverrides[receipt.id]
            ?? V02ReceiptTemplate.recommended(for: receipt, resources: store.state.resources)
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

struct V04ReceiptReaderView: View {
    @ObservedObject var store: V02Store
    let receipts: [V02Receipt]
    let initialReceiptID: UUID
    let onDelete: (Set<UUID>) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index: Int
    @State private var dragAxis: V02ReceiptGestureAxis = .none
    @State private var dragTranslation: CGFloat = 0
    @State private var transitionTargetIndex: Int?

    init(
        store: V02Store,
        receipts: [V02Receipt],
        initialReceiptID: UUID,
        onDelete: @escaping (Set<UUID>) -> Void
    ) {
        self.store = store
        self.receipts = receipts
        self.initialReceiptID = initialReceiptID
        self.onDelete = onDelete
        _index = State(initialValue: receipts.firstIndex(where: { $0.id == initialReceiptID }) ?? 0)
    }

    var body: some View {
        GeometryReader { proxy in
            let targetIndex = visibleTargetIndex
            let transition = V04ReceiptSwitchTransitionPolicy.layout(
                translation: dragTranslation,
                extent: proxy.size.width,
                hasTarget: targetIndex != nil,
                reduceMotion: reduceMotion
            )
            ZStack {
                Rectangle()
                    .fill(V04ObjectTransitionSurfacePolicy.style(for: V04ObjectTransitionSurfacePolicy.receiptReaderHost))
                    .ignoresSafeArea()

                if let targetIndex, receipts.indices.contains(targetIndex) {
                    receiptDetail(at: targetIndex)
                        .offset(x: transition.targetOffset)
                        .scaleEffect(transition.targetScale)
                        .opacity(targetOpacity(for: dragTranslation, extent: proxy.size.width))
                        .accessibilityHidden(true)
                        .allowsHitTesting(false)
                }

                if receipts.indices.contains(index) {
                    receiptDetail(at: index)
                        .offset(x: transition.currentOffset)
                        .scaleEffect(transition.currentScale)
                        .opacity(currentOpacity(for: dragTranslation, extent: proxy.size.width, hasTarget: targetIndex != nil))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .simultaneousGesture(receiptSwitchGesture(extent: proxy.size.width))
        }
        .accessibilityAdjustableAction { direction in
            guard !receipts.isEmpty else { return }
            switch direction {
            case .increment:
                index = min(index + 1, receipts.count - 1)
            case .decrement:
                index = max(index - 1, 0)
            @unknown default:
                break
            }
        }
    }

    private func receiptDetail(at itemIndex: Int) -> some View {
        V02ReceiptDetailView(
            store: store,
            receipt: receipts[itemIndex],
            onDelete: onDelete,
            usesSharedReaderCanvas: true
        )
        .id(receipts[itemIndex].id)
    }

    private var visibleTargetIndex: Int? {
        if let transitionTargetIndex {
            return transitionTargetIndex
        }
        guard dragAxis == .horizontal else { return nil }
        return V02ReceiptGesturePolicy.candidateIndex(
            index: index,
            count: receipts.count,
            translation: dragTranslation
        )
    }

    private func currentOpacity(
        for translation: CGFloat,
        extent: CGFloat,
        hasTarget: Bool
    ) -> Double {
        guard reduceMotion, hasTarget else { return 1 }
        let progress = min(abs(translation) / max(abs(extent), 1), 1)
        return Double(1 - progress)
    }

    private func targetOpacity(for translation: CGFloat, extent: CGFloat) -> Double {
        guard reduceMotion else { return 1 }
        let progress = min(abs(translation) / max(abs(extent), 1), 1)
        return Double(progress)
    }

    private func receiptSwitchGesture(extent: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: V02ReceiptGesturePolicy.lockDistance)
            .onChanged { value in
                guard transitionTargetIndex == nil else { return }
                if dragAxis == .none {
                    guard V02ReceiptGesturePolicy.axis(for: value.translation) == .horizontal else {
                        return
                    }
                    dragAxis = .horizontal
                }
                guard dragAxis == .horizontal else { return }
                dragTranslation = value.translation.width
            }
            .onEnded { value in
                guard transitionTargetIndex == nil else { return }
                guard dragAxis == .horizontal else {
                    dragTranslation = 0
                    return
                }

                let candidate = V02ReceiptGesturePolicy.candidateIndex(
                    index: index,
                    count: receipts.count,
                    translation: value.translation.width
                )
                let target = V02ReceiptGesturePolicy.horizontalTarget(
                    index: index,
                    count: receipts.count,
                    translation: value.translation.width,
                    predictedEndTranslation: value.predictedEndTranslation.width
                )
                let duration: TimeInterval = reduceMotion ? 0.16 : 0.30

                if let target {
                    transitionTargetIndex = target
                    let direction: CGFloat = value.translation.width < 0 ? -1 : 1
                    let finalTranslation = direction * max(abs(extent), 1)
                    withAnimation(
                        reduceMotion
                            ? .easeOut(duration: duration)
                            : .smooth(duration: duration)
                    ) {
                        dragTranslation = finalTranslation
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.01) {
                        guard transitionTargetIndex == target else { return }
                        index = target
                        dragTranslation = 0
                        transitionTargetIndex = nil
                        dragAxis = .none
                    }
                } else {
                    // Keep any revealed neighbour in the stack while the
                    // current receipt returns to centre. The index is never
                    // changed for an under-threshold or boundary attempt.
                    transitionTargetIndex = candidate
                    withAnimation(NoteMotion.settle(reduceMotion: reduceMotion)) {
                        dragTranslation = 0
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.01) {
                        guard transitionTargetIndex == candidate else { return }
                        transitionTargetIndex = nil
                        dragAxis = .none
                    }
                }
            }
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
