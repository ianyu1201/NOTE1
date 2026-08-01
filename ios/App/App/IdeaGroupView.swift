import SwiftUI

struct IdeaGroupView: View {
    @ObservedObject var store: NoteStore
    let groupID: UUID
    let onOpenIdea: (UUID) -> Void

    @State private var editingName = false
    @State private var name = ""
    @State private var showComposer = false
    @State private var errorAlert: UserFacingAlert?
    @FocusState private var nameFocused: Bool

    private var group: IdeaGroup? { store.group(id: groupID) }
    private var ideas: [Idea] { store.ideas(in: groupID) }
    private var isGroupActive: Bool { group?.status == .active }

    var body: some View {
        VStack(spacing: 18) {
            if let group {
                HStack(spacing: 12) {
                    if editingName {
                        TextField("灵感组名称", text: $name)
                            .font(.largeTitle.bold())
                            .focused($nameFocused)
                            .onSubmit(saveName)
                    } else {
                        Text(group.name)
                            .font(.largeTitle.bold())
                    }
                    Spacer()
                    if isGroupActive {
                        RoundGlassButton(
                            systemName: editingName ? "checkmark" : "square.and.pencil",
                            label: editingName ? "保存灵感组名称" : "编辑灵感组名称",
                            action: editingName ? saveName : beginEditingName
                        )
                    }
                }

                if ideas.isEmpty {
                    EmptyStateView(
                        systemName: isGroupActive
                            ? "rectangle.stack.badge.plus"
                            : "checkmark.circle",
                        title: "这个灵感组还是空的",
                        message: isGroupActive
                            ? "可以从卡片页把灵感加入这里。"
                            : "恢复整个灵感组后，才能继续添加内容。"
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(ideas.enumerated()), id: \.element.id) {
                                offset,
                                idea in
                                timelineRow(
                                    idea,
                                    sequence: offset + 1,
                                    isLast: offset == ideas.count - 1
                                )
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .scrollIndicators(.visible)
                    .scrollBounceBehavior(.basedOnSize)
                }

                if isGroupActive {
                    Button {
                        showComposer = true
                    } label: {
                        Label("新增", systemImage: "plus")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                    }
                    .buttonStyle(PressScaleButtonStyle())
                    .noteGlass(cornerRadius: 28)
                }
            } else {
                EmptyStateView(
                    systemName: "exclamationmark.circle",
                    title: "找不到灵感组",
                    message: "它可能已被删除。"
                )
                .frame(maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, NoteTheme.horizontalPadding)
        .padding(.top, 24)
        .padding(.bottom, 12)
        .onAppear { name = group?.name ?? "" }
        .onChange(of: group?.name) { _, nextName in
            guard !editingName else { return }
            name = nextName ?? ""
        }
        .sheet(isPresented: $showComposer) {
            GroupIdeaComposer(store: store, groupID: groupID)
        }
        .noteErrorAlert($errorAlert)
    }

    private func timelineRow(
        _ idea: Idea,
        sequence: Int,
        isLast: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 6) {
                Text("\(sequence)")
                    .noteFont(
                        size: 12,
                        weight: .semibold,
                        design: .rounded,
                        relativeTo: .caption
                    )
                    .foregroundStyle(NoteTheme.accent)
                    .frame(width: 30, height: 30)
                    .background(
                        NoteTheme.accent.opacity(0.1),
                        in: Circle()
                    )
                    .overlay {
                        Circle()
                            .stroke(
                                NoteTheme.accent.opacity(0.24),
                                lineWidth: 1
                            )
                    }

                if !isLast {
                    Rectangle()
                        .fill(NoteTheme.accent.opacity(0.18))
                        .frame(width: 1.5)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 30)
            .frame(maxHeight: .infinity)
            .accessibilityHidden(true)

            HStack(alignment: .top, spacing: 8) {
                Button {
                    onOpenIdea(idea.id)
                } label: {
                    VStack(alignment: .leading, spacing: 9) {
                        Text(
                            NoteDateFormatter.display(
                                idea.addedToGroupAt ?? idea.createdAt
                            )
                        )
                        .noteFont(size: 12, relativeTo: .caption)
                        .foregroundStyle(NoteTheme.secondaryInk)

                        Text(idea.content.isEmpty ? "未命名想法" : idea.content)
                            .noteFont(size: 16, relativeTo: .body)
                            .foregroundStyle(NoteTheme.ink)
                            .multilineTextAlignment(.leading)
                            .lineLimit(6)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    "第 \(sequence) 条思考，\(idea.content.isEmpty ? "未命名想法" : idea.content)"
                )
                .accessibilityHint("点按打开编辑")

                if isGroupActive {
                    Button {
                        removeFromGroup(idea.id)
                    } label: {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(PressScaleButtonStyle())
                    .contentShape(Rectangle())
                    .accessibilityLabel(
                        "将 \(idea.content.isEmpty ? "未命名想法" : idea.content) 移出灵感组"
                    )
                }
            }
            .padding(16)
            .background(
                Color.white.opacity(0.22),
                in: RoundedRectangle(
                    cornerRadius: 20,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 20,
                    style: .continuous
                )
                .stroke(Color.white.opacity(0.5), lineWidth: 1)
            }
            .padding(.bottom, isLast ? 0 : 14)
        }
    }

    private func beginEditingName() {
        guard isGroupActive else { return }
        name = group?.name ?? ""
        editingName = true
        DispatchQueue.main.async {
            nameFocused = true
        }
    }

    private func saveName() {
        let nextName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nextName.isEmpty else { return }
        do {
            try store.renameGroup(id: groupID, name: nextName)
            nameFocused = false
            editingName = false
        } catch {
            present(error)
        }
    }

    private func removeFromGroup(_ ideaID: UUID) {
        do {
            try store.removeIdeaFromGroup(ideaID)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            present(error)
        }
    }

    private func present(_ error: Error) {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        errorAlert = UserFacingAlert.local(error: error)
    }
}
