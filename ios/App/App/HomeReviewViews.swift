import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct HomeView: View {
    @ObservedObject var store: NoteStore
    let onReview: () -> Void
    let onOpenIdea: (UUID) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draft = ""
    @State private var draftAttachments: [AttachmentInput] = []
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var showAttachmentSource = false
    @State private var showPhotoPicker = false
    @State private var showFileImporter = false
    @State private var errorAlert: UserFacingAlert?
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            if !store.recentActiveIdeas.isEmpty {
                recentIdeas
                    .frame(maxHeight: 238)
                    .transition(
                        .move(edge: .bottom)
                            .combined(with: .opacity)
                    )
            }

            Spacer(minLength: 20)

            HStack(alignment: .bottom, spacing: 14) {
                HStack(alignment: .bottom, spacing: 12) {
                    Button {
                        showAttachmentSource = true
                    } label: {
                        Image(systemName: draftAttachments.isEmpty ? "plus" : "paperclip")
                            .font(.system(size: 20, weight: .semibold))
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("添加附件")

                    TextField(
                        "记录此刻的想法……",
                        text: $draft,
                        axis: .vertical
                    )
                        .focused($inputFocused)
                        .lineLimit(1...5)
                        .frame(minHeight: 48, alignment: .center)
                        .submitLabel(.send)
                        .onSubmit(saveDraft)

                    Button(action: saveDraft) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(hasSaveableDraft ? .white : NoteTheme.secondaryInk)
                            .frame(width: 48, height: 48)
                            .background(
                                hasSaveableDraft ? NoteTheme.ink : Color.white.opacity(0.3),
                                in: Circle()
                            )
                    }
                    .buttonStyle(PressScaleButtonStyle())
                    .disabled(!hasSaveableDraft)
                    .accessibilityLabel("保存想法")
                }
                .padding(.leading, 20)
                .padding(.trailing, 8)
                .padding(.vertical, 8)
                .frame(minHeight: 64)
                .noteGlass(cornerRadius: 32, castsShadow: false)

                RoundGlassButton(
                    systemName: "square.on.square",
                    label: "进入卡片回看",
                    size: 64,
                    iconSize: 20,
                    action: onReview
                )
            }
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, NoteTheme.horizontalPadding)
        .contentShape(Rectangle())
        .overlay {
            if showAttachmentSource {
                ZStack(alignment: .bottom) {
                    Color.clear

                    AttachmentSourcePanel(
                        onSelect: { source in
                            showAttachmentSource = false
                            presentAttachmentPicker(source)
                        },
                        onCancel: {
                            showAttachmentSource = false
                        }
                    )
                    .padding(.horizontal, 18)
                    .padding(.bottom, 96)
                    .transition(
                        .move(edge: .bottom)
                            .combined(with: .opacity)
                            .combined(with: .scale(scale: 0.96, anchor: .bottom))
                    )
                }
            }
        }
        .animation(
            reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.82),
            value: showAttachmentSource
        )
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            do {
                let urls = try result.get()
                draftAttachments.append(
                    contentsOf: try urls.map(AttachmentImporter.input)
                )
            } catch {
                present(error)
            }
        }
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $selectedPhotoItems,
            maxSelectionCount: 10,
            matching: .images
        )
        .onChange(of: selectedPhotoItems) { _, items in
            importPhotos(items)
        }
        .noteErrorAlert($errorAlert)
    }

    @ViewBuilder
    private var recentIdeas: some View {
        VStack(spacing: 0) {
            ForEach(Array(store.recentActiveIdeas.prefix(5))) { idea in
                Button {
                    onOpenIdea(idea.id)
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(idea.content.isEmpty ? "未命名想法" : idea.content)
                                .font(.system(size: 14, weight: .semibold))
                                .lineLimit(1)
                                .multilineTextAlignment(.leading)
                            Text(NoteDateFormatter.display(idea.activityAt))
                                .font(.system(size: 11))
                                .foregroundStyle(NoteTheme.secondaryInk)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(NoteTheme.secondaryInk)
                    }
                    .padding(.vertical, 7)
                    .padding(.horizontal, 16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transition(
                    .move(edge: .bottom)
                        .combined(with: .opacity)
                        .combined(with: .scale(scale: 0.97))
                )

                if idea.id != store.recentActiveIdeas.prefix(5).last?.id {
                    Divider()
                        .overlay(NoteTheme.divider)
                        .padding(.horizontal, 16)
                }
            }
        }
        .noteGlass(cornerRadius: 22, strokeOpacity: 0.55)
        .animation(
            reduceMotion ? nil : .spring(response: 0.44, dampingFraction: 0.82),
            value: store.recentActiveIdeas.prefix(5).map(\.id)
        )
    }

    private func saveDraft() {
        let content = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty || !draftAttachments.isEmpty else { return }
        do {
            _ = try withAnimation(
                reduceMotion ? nil : .spring(response: 0.44, dampingFraction: 0.82)
            ) {
                try store.createIdea(
                    content: content,
                    attachmentInputs: draftAttachments
                )
            }
            draft = ""
            draftAttachments = []
            inputFocused = false
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            present(error)
        }
    }

    private var hasSaveableDraft: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || !draftAttachments.isEmpty
    }

    private func importPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        Task { @MainActor in
            let inputs = await photoAttachmentInputs(from: items)
            draftAttachments.append(contentsOf: inputs)
            selectedPhotoItems = []
            if inputs.isEmpty {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                errorAlert = UserFacingAlert(message: "没有读到可添加的照片，请重新选择。")
            }
        }
    }

    private func present(_ error: Error) {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        errorAlert = UserFacingAlert.local(error: error)
    }

    private func presentAttachmentPicker(_ source: AttachmentSource) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            switch source {
            case .photos:
                showPhotoPicker = true
            case .files:
                showFileImporter = true
            }
        }
    }
}

struct ReviewView: View {
    @ObservedObject var store: NoteStore
    let onOpenIdea: (UUID) -> Void
    let onOpenGroup: (UUID) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0
    @State private var dragOffset: CGSize = .zero
    @State private var dragAxis: ReviewDragAxis?
    @State private var showGroupPicker = false
    @State private var groupingIdeaID: UUID?
    @State private var groupMenuExpanded = false
    @State private var hoveredGroupID: UUID?
    @State private var hoveringNew = false
    @State private var groupButtonFrame: CGRect = .zero
    @State private var groupTargetFrames: [String: CGRect] = [:]
    @State private var suppressCardGesture = false
    @State private var cardPresented = true
    @State private var isCompleting = false
    @State private var undoItem: ReviewItem?
    @State private var undoDismissTask: DispatchWorkItem?
    @State private var errorAlert: UserFacingAlert?
    @GestureState private var groupButtonPressed = false

    private var items: [ReviewItem] { store.reviewItems }
    private var quickGroups: [IdeaGroup] { Array(store.activeGroups.prefix(3)) }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                Group {
                    if items.isEmpty {
                        EmptyStateView(
                            systemName: "rectangle.stack",
                            title: "本轮已经看完",
                            message: "新的想法会自动进入卡片回看。"
                        )
                    } else {
                        cardStage
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let currentItem {
                    groupActionButton(for: currentItem)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: GroupButtonFrameKey.self,
                                value: proxy.frame(in: .named("reviewCanvas"))
                            )
                        }
                    }
                    .padding(.bottom, 56)
                }
            }

            if groupMenuExpanded {
                GroupDropTray(
                    groups: quickGroups,
                    showNew: true,
                    hoveredGroupID: hoveredGroupID,
                    hoveringNew: hoveringNew
                )
                .padding(.horizontal, 8)
                .padding(.bottom, 128)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .allowsHitTesting(false)
            }

        }
        .overlay(alignment: .bottom) {
            if let undoItem {
                CompletionUndoBanner(
                    title: undoItem.title,
                    onUndo: undoCompletion
                )
                .padding(.horizontal, 14)
                .padding(.bottom, 82)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .coordinateSpace(name: "reviewCanvas")
        .onPreferenceChange(GroupButtonFrameKey.self) { groupButtonFrame = $0 }
        .onPreferenceChange(GroupTargetFramesKey.self) { groupTargetFrames = $0 }
        .padding(.horizontal, NoteTheme.horizontalPadding)
        .sheet(isPresented: $showGroupPicker) {
            if case .idea(let idea) = currentItem {
                GroupPickerView(store: store, ideaID: idea.id)
            } else {
                IdeaGroupsListView(store: store, onOpenGroup: onOpenGroup)
            }
        }
        .onChange(of: items.count) { _, count in
            index = min(index, max(0, count - 1))
        }
        .noteErrorAlert($errorAlert)
    }

    @ViewBuilder
    private func groupActionButton(for item: ReviewItem) -> some View {
        switch item {
        case .idea(let idea):
            RoundGlassButton(
                systemName: "rectangle.stack.badge.plus",
                label: "灵感组",
                size: 64,
                iconSize: 23,
                externallyPressed: groupButtonPressed,
                action: { showGroupPicker = true }
            )
            .highPriorityGesture(groupButtonGesture(for: idea))
            .accessibilityHint("点按选择灵感组；按住并向上拖动可快速归组")
        case .group:
            RoundGlassButton(
                systemName: "rectangle.stack.badge.plus",
                label: "灵感组",
                size: 64,
                iconSize: 23,
                action: {}
            )
            .disabled(true)
            .opacity(0.3)
        }
    }

    private var currentItem: ReviewItem? {
        guard items.indices.contains(index) else { return nil }
        return items[index]
    }

    private var cardStage: some View {
        GeometryReader { proxy in
            ZStack {
                if let item = currentItem {
                    if dragAxis == .horizontal, completionCueProgress > 0 {
                        VStack(spacing: 9) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 40, weight: .semibold))
                            Text("完成")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(
                            NoteTheme.accent.opacity(0.18 + completionCueProgress * 0.26)
                        )
                        .scaleEffect(0.9 + completionCueProgress * 0.08)
                        .opacity(completionCueProgress)
                    }

                    ReviewCardView(
                        item: item,
                        ideaCount: ideaCount(for: item)
                    )
                    .id(item.id)
                    .offset(dragOffset)
                    .rotationEffect(.degrees(Double(dragOffset.width / 34)))
                    .opacity(max(0.2, 1 - abs(dragOffset.width) / max(1, proxy.size.width)))
                    .scaleEffect(1 - min(abs(dragOffset.height) / 1800, 0.06))
                    .offset(y: cardPresented ? 0 : 34)
                    .scaleEffect(cardPresented ? 1 : 0.94)
                    .opacity(cardPresented ? 1 : 0)
                    .scaleEffect(groupingIdeaID == item.id ? 0.96 : 1)
                    .opacity(groupingIdeaID == item.id ? 0.52 : 1)
                    .contentShape(RoundedRectangle(cornerRadius: 38, style: .continuous))
                    .onTapGesture {
                        guard !suppressCardGesture,
                              groupingIdeaID == nil,
                              !isCompleting
                        else { return }
                        open(item)
                    }
                    .gesture(reviewGesture(for: item, containerSize: proxy.size))
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("review.card.\(item.id.uuidString)")
                    .accessibilityHint("点按编辑；上下滑动切换；左右滑动完成")
                    .accessibilityAction(.default) {
                        open(item)
                    }
                    .accessibilityAction(named: "查看上一条") {
                        page(direction: -1, height: proxy.size.height)
                    }
                    .accessibilityAction(named: "查看下一条") {
                        page(direction: 1, height: proxy.size.height)
                    }
                    .accessibilityAction(named: "完成这条灵感") {
                        completeCurrent(direction: 1, width: proxy.size.width)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.vertical, 28)
    }

    private func ideaCount(for item: ReviewItem) -> Int {
        guard case .group(let group) = item else { return 0 }
        return store.ideas(in: group.id).count
    }

    private var completionCueProgress: Double {
        let distance = abs(dragOffset.width)
        return min(max((distance - 76) / 84, 0), 1)
    }

    private func reviewGesture(
        for item: ReviewItem,
        containerSize: CGSize
    ) -> some Gesture {
        DragGesture(
            minimumDistance: 0,
            coordinateSpace: .named("reviewCanvas")
        )
            .onChanged { value in
                guard !isCompleting else { return }

                if dragAxis == nil {
                    dragAxis = ReviewGestureClassifier.axis(
                        for: value.translation
                    )
                    guard dragAxis != nil else { return }
                }

                switch dragAxis {
                case .horizontal:
                    dragOffset = CGSize(
                        width: value.translation.width,
                        height: value.translation.height * 0.06
                    )
                case .vertical:
                    dragOffset = CGSize(
                        width: value.translation.width * 0.04,
                        height: value.translation.height
                    )
                case nil:
                    break
                }
            }
            .onEnded { value in
                guard !isCompleting else { return }

                if ReviewGestureClassifier.shouldComplete(
                    axis: dragAxis,
                    translation: value.translation,
                    predictedEndTranslation: value.predictedEndTranslation
                ) {
                    completeCurrent(
                        direction: value.predictedEndTranslation.width < 0 ? -1 : 1,
                        width: containerSize.width
                    )
                } else if ReviewGestureClassifier.shouldPage(
                    axis: dragAxis,
                    translation: value.translation,
                    predictedEndTranslation: value.predictedEndTranslation
                ) {
                    page(
                        direction: value.predictedEndTranslation.height < 0 ? 1 : -1,
                        height: containerSize.height
                    )
                } else {
                    settle()
                }
            }
    }

    private func groupButtonGesture(for idea: Idea) -> some Gesture {
        DragGesture(
            minimumDistance: 0,
            coordinateSpace: .named("reviewCanvas")
        )
        .updating($groupButtonPressed) { _, pressed, _ in
            pressed = true
        }
        .onChanged { value in
            guard !isCompleting else { return }
            let distance = hypot(
                value.translation.width,
                value.translation.height
            )

            if groupingIdeaID == nil, distance >= 8 {
                beginGrouping(ideaID: idea.id)
            }

            guard groupingIdeaID == idea.id else { return }
            updateGroupTarget(at: value.location)
        }
        .onEnded { value in
            guard !isCompleting else { return }

            if groupingIdeaID == idea.id {
                updateGroupTarget(at: value.location)
                finishGrouping(ideaID: idea.id)
            } else {
                showGroupPicker = true
            }
        }
    }

    private func beginGrouping(ideaID: UUID) {
        guard groupingIdeaID == nil else { return }
        groupingIdeaID = ideaID
        suppressCardGesture = true
        dragOffset = .zero
        dragAxis = nil
        withAnimation(
            reduceMotion
                ? nil
                : .spring(response: 0.3, dampingFraction: 0.8)
        ) {
            groupMenuExpanded = true
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func updateGroupTarget(at location: CGPoint) {
        if !groupMenuExpanded,
           groupButtonFrame.insetBy(dx: -54, dy: -54).contains(location) {
            withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.78)) {
                groupMenuExpanded = true
            }
        }
        guard groupMenuExpanded else { return }

        let previousGroupID = hoveredGroupID
        let previousNew = hoveringNew

        let groupFrames = Dictionary(
            uniqueKeysWithValues: quickGroups.compactMap { group in
                groupTargetFrames[group.id.uuidString].map { (group.id, $0) }
            }
        )
        let target = ReviewGroupDropClassifier.target(
            at: location,
            groupFrames: groupFrames,
            newFrame: groupTargetFrames["new"]
        )

        switch target {
        case .group(let groupID):
            hoveredGroupID = groupID
            hoveringNew = false
        case .new:
            hoveredGroupID = nil
            hoveringNew = true
        case nil:
            hoveredGroupID = nil
            hoveringNew = false
        }

        if previousGroupID != hoveredGroupID || previousNew != hoveringNew {
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    private func finishGrouping(ideaID: UUID) {
        let targetGroupID = hoveredGroupID

        if let targetGroupID {
            do {
                try store.assignIdea(ideaID, to: targetGroupID)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                present(error)
            }
        } else if hoveringNew {
            showGroupPicker = true
        }

        resetGroupingState()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            suppressCardGesture = false
        }
    }

    private func resetGroupingState() {
        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.82)) {
            groupingIdeaID = nil
            groupMenuExpanded = false
            hoveredGroupID = nil
            hoveringNew = false
            dragOffset = .zero
            dragAxis = nil
        }
    }

    private func settle() {
        withAnimation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.76)) {
            dragOffset = .zero
            dragAxis = nil
        }
    }

    private func page(direction: Int, height: CGFloat) {
        dragAxis = nil
        let nextIndex = index + direction
        guard items.indices.contains(nextIndex) else {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            settle()
            return
        }

        let change = {
            index = nextIndex
            dragOffset = CGSize(width: 0, height: direction > 0 ? height : -height)
            withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.84)) {
                dragOffset = .zero
            }
            UISelectionFeedbackGenerator().selectionChanged()
        }

        guard !reduceMotion else {
            change()
            return
        }
        withAnimation(.easeIn(duration: 0.16)) {
            dragOffset.height = direction > 0 ? -height : height
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: change)
    }

    private func completeCurrent(direction: CGFloat, width: CGFloat) {
        guard let item = currentItem, !isCompleting else { return }
        isCompleting = true

        let finish = {
            do {
                cardPresented = false
                try store.complete(item)
                dragOffset = .zero
                dragAxis = nil
                index = min(index, max(0, items.count - 1))
                showUndo(for: item)
                UINotificationFeedbackGenerator().notificationOccurred(.success)

                if currentItem != nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                        withAnimation(
                            reduceMotion
                                ? .easeOut(duration: 0.12)
                                : .spring(response: 0.48, dampingFraction: 0.82)
                        ) {
                            cardPresented = true
                        }
                    }
                    DispatchQueue.main.asyncAfter(
                        deadline: .now() + (reduceMotion ? 0.16 : 0.4)
                    ) {
                        isCompleting = false
                    }
                } else {
                    cardPresented = true
                    isCompleting = false
                }
            } catch {
                dragOffset = .zero
                cardPresented = true
                isCompleting = false
                present(error)
            }
        }
        guard !reduceMotion else {
            finish()
            return
        }
        withAnimation(.easeIn(duration: 0.28)) {
            dragOffset.width = direction * (width + 120)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28, execute: finish)
    }

    private func showUndo(for item: ReviewItem) {
        undoDismissTask?.cancel()
        withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) {
            undoItem = item
        }

        let task = DispatchWorkItem {
            guard undoItem?.id == item.id else { return }
            withAnimation(.easeOut(duration: 0.22)) {
                undoItem = nil
            }
        }
        undoDismissTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 7, execute: task)
    }

    private func undoCompletion() {
        guard let item = undoItem else { return }
        undoDismissTask?.cancel()
        do {
            try store.restore(item)
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                index = 0
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                guard undoItem?.id == item.id else { return }
                withAnimation(.easeOut(duration: 0.18)) {
                    undoItem = nil
                }
            }
        } catch {
            present(error)
        }
    }

    private func open(_ item: ReviewItem) {
        switch item {
        case .idea(let idea): onOpenIdea(idea.id)
        case .group(let group): onOpenGroup(group.id)
        }
    }

    private func present(_ error: Error) {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        errorAlert = UserFacingAlert.local(error: error)
    }
}

private struct GroupButtonFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

enum ReviewDragAxis: Equatable {
    case horizontal
    case vertical
}

enum ReviewGestureClassifier {
    static func axis(for translation: CGSize) -> ReviewDragAxis? {
        let horizontal = abs(translation.width)
        let vertical = abs(translation.height)
        guard max(horizontal, vertical) >= 14 else { return nil }

        if horizontal >= vertical * 1.35 {
            return .horizontal
        }
        if vertical >= horizontal * 1.18 {
            return .vertical
        }
        return nil
    }

    static func shouldComplete(
        axis: ReviewDragAxis?,
        translation: CGSize,
        predictedEndTranslation: CGSize
    ) -> Bool {
        guard axis == .horizontal else { return false }
        return abs(translation.width) > 110
            || abs(predictedEndTranslation.width) > 190
    }

    static func shouldPage(
        axis: ReviewDragAxis?,
        translation: CGSize,
        predictedEndTranslation: CGSize
    ) -> Bool {
        guard axis == .vertical else { return false }
        return abs(translation.height) > 64
            || abs(predictedEndTranslation.height) > 96
    }
}

private struct GroupTargetFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(
        value: inout [String: CGRect],
        nextValue: () -> [String: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

enum ReviewGroupDropTarget: Equatable {
    case group(UUID)
    case new
}

struct ReviewGroupDropClassifier {
    static func target(
        at location: CGPoint,
        groupFrames: [UUID: CGRect],
        newFrame: CGRect?
    ) -> ReviewGroupDropTarget? {
        if let group = groupFrames.first(where: { $0.value.contains(location) }) {
            return .group(group.key)
        }
        if newFrame?.contains(location) == true {
            return .new
        }
        return nil
    }
}

private struct GroupDropTray: View {
    let groups: [IdeaGroup]
    let showNew: Bool
    let hoveredGroupID: UUID?
    let hoveringNew: Bool

    var body: some View {
        HStack(spacing: 10) {
            ForEach(groups) { group in
                target(
                    key: group.id.uuidString,
                    title: group.name,
                    systemName: "rectangle.stack.fill",
                    highlighted: hoveredGroupID == group.id
                )
            }
            if showNew {
                target(
                    key: "new",
                    title: "新建",
                    systemName: "plus",
                    highlighted: hoveringNew
                )
            }
        }
        .padding(10)
        .background(
            NoteTheme.ink.opacity(0.035),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .noteGlass(cornerRadius: 28)
    }

    private func target(
        key: String,
        title: String,
        systemName: String,
        highlighted: Bool
    ) -> some View {
        VStack(spacing: 5) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .semibold))
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(highlighted ? .white : NoteTheme.ink)
        .frame(maxWidth: .infinity)
        .frame(height: 62)
        .background(
            highlighted ? NoteTheme.accent : NoteTheme.ink.opacity(0.035),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
        )
        .scaleEffect(highlighted ? 1.06 : 1)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: GroupTargetFramesKey.self,
                    value: [key: proxy.frame(in: .named("reviewCanvas"))]
                )
            }
        }
        .accessibilityLabel(title)
        .accessibilityIdentifier("review.groupTarget.\(key)")
    }
}

private struct ReviewCardView: View {
    let item: ReviewItem
    let ideaCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer(minLength: 0)

            switch item {
            case .idea(let idea):
                Text(NoteDateFormatter.display(idea.createdAt))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(NoteTheme.secondaryInk)
                Text(idea.content.isEmpty ? "未命名想法" : idea.content)
                    .font(.system(size: 20, weight: .regular, design: .rounded))
                    .lineSpacing(6)
                    .lineLimit(10)
            case .group(let group):
                Label("灵感组", systemImage: "rectangle.stack.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(NoteTheme.secondaryInk)
                Text(group.name)
                    .font(.system(size: 31, weight: .bold, design: .rounded))
                Text("\(ideaCount) 条想法")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(NoteTheme.secondaryInk)
            }

            Spacer(minLength: 0)

            HStack {
                Label("上下切换", systemImage: "arrow.up.arrow.down")
                Spacer()
                Label("左右完成", systemImage: "arrow.left.and.right")
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(NoteTheme.secondaryInk)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .noteGlass(cornerRadius: 38)
    }
}

private struct CompletionUndoBanner: View {
    let title: String
    let onUndo: () -> Void

    var body: some View {
        Button(action: onUndo) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(NoteTheme.accent)
                Text("已完成")
                    .font(.system(size: 14, weight: .semibold))
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(NoteTheme.secondaryInk)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("撤回")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(NoteTheme.accent)
            }
            .padding(.horizontal, 18)
            .frame(height: 54)
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleButtonStyle())
        .noteGlass(cornerRadius: 27)
        .accessibilityLabel("撤回完成，\(title)")
        .accessibilityIdentifier("review.completion.undo")
    }
}
