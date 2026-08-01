import SwiftUI

struct ReviewView: View {
    @ObservedObject var store: NoteStore
    @Binding var selectedItemID: UUID?
    let onOpenIdea: (UUID) -> Void
    let onOpenGroup: (UUID) -> Void

    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State var index = 0
    @State var dragOffset: CGSize = .zero
    @State var dragAxis: ReviewDragAxis?
    @State var showGroupPicker = false
    @State var groupingIdeaID: UUID?
    @State var groupMenuExpanded = false
    @State var hoveredGroupID: UUID?
    @State var hoveringNew = false
    @State var groupButtonFrame: CGRect = .zero
    @State var groupTargetFrames: [String: CGRect] = [:]
    @State var suppressCardGesture = false
    @State var cardPresented = true
    @State var isCompleting = false
    @State var undoItem: ReviewItem?
    @State var undoDismissTask: DispatchWorkItem?
    @State var errorAlert: UserFacingAlert?
    @GestureState var groupButtonPressed = false

    var items: [ReviewItem] { store.reviewItems }
    var quickGroups: [IdeaGroup] { Array(store.activeGroups.prefix(3)) }

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
                .accessibilityHidden(true)
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
        .onAppear {
            synchronizeSelection()
        }
        .onChange(of: items.map(\.id)) { _, _ in
            synchronizeSelection()
        }
        .onChange(of: index) { _, _ in
            publishCurrentSelection()
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

    var currentItem: ReviewItem? {
        guard items.indices.contains(index) else { return nil }
        return items[index]
    }

    private func synchronizeSelection() {
        guard let resolvedIndex = ReviewPositionPolicy.resolvedIndex(
            preferredItemID: selectedItemID,
            currentIndex: index,
            itemIDs: items.map(\.id)
        ) else {
            index = 0
            selectedItemID = nil
            return
        }
        index = resolvedIndex
        selectedItemID = items[resolvedIndex].id
    }

    private func publishCurrentSelection() {
        guard items.indices.contains(index) else {
            selectedItemID = nil
            return
        }
        selectedItemID = items[index].id
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
                                .noteFont(
                                    size: 14,
                                    weight: .semibold,
                                    design: .rounded,
                                    relativeTo: .subheadline
                                )
                        }
                        .foregroundStyle(
                            NoteTheme.accent.opacity(0.18 + completionCueProgress * 0.26)
                        )
                        .scaleEffect(0.9 + completionCueProgress * 0.08)
                        .opacity(completionCueProgress)
                        .accessibilityHidden(true)
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
                    .accessibilityLabel(accessibilityLabel(for: item))
                    .accessibilityValue("第 \(index + 1) 条，共 \(items.count) 条")
                    .accessibilityHint("点按编辑；上下滑动切换；向左滑动完成")
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
                        completeCurrent(direction: -1, width: proxy.size.width)
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

    private func accessibilityLabel(for item: ReviewItem) -> String {
        switch item {
        case .idea(let idea):
            return idea.content.isEmpty ? "未命名想法" : idea.content
        case .group(let group):
            return "灵感组，\(group.name)，\(ideaCount(for: item)) 条想法"
        }
    }

}
