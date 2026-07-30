import SwiftUI

struct GroupPickerView: View {
    @ObservedObject var store: NoteStore
    let ideaID: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var newGroupName = ""
    @State private var errorAlert: UserFacingAlert?

    var body: some View {
        NavigationStack {
            List {
                Section("选择灵感组") {
                    ForEach(store.activeGroups) { group in
                        Button {
                            assign(to: group.id)
                        } label: {
                            Label(group.name, systemImage: "rectangle.stack.fill")
                        }
                        .accessibilityLabel("加入灵感组 \(group.name)")
                    }
                }

                Section("新建灵感组") {
                    HStack {
                        TextField("输入名称", text: $newGroupName)
                        Button("创建") { createGroup() }
                            .disabled(newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .navigationTitle("灵感组")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .noteErrorAlert($errorAlert)
    }

    private func assign(to groupID: UUID) {
        do {
            try store.assignIdea(ideaID, to: groupID)
            dismiss()
        } catch {
            present(error)
        }
    }

    private func createGroup() {
        let groupName = newGroupName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !groupName.isEmpty else { return }
        do {
            _ = try store.createGroup(name: groupName, initialIdeaID: ideaID)
            dismiss()
        } catch {
            present(error)
        }
    }

    private func present(_ error: Error) {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        errorAlert = UserFacingAlert.local(error: error)
    }
}

struct IdeaGroupsListView: View {
    @ObservedObject var store: NoteStore
    let onOpenGroup: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(store.activeGroups) { group in
                Button {
                    dismiss()
                    DispatchQueue.main.async { onOpenGroup(group.id) }
                } label: {
                    HStack {
                        Label(group.name, systemImage: "rectangle.stack.fill")
                        Spacer()
                        Text("\(store.ideas(in: group.id).count)")
                            .foregroundStyle(NoteTheme.secondaryInk)
                    }
                }
            }
            .navigationTitle("灵感组")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}

struct GroupIdeaComposer: View {
    @ObservedObject var store: NoteStore
    let groupID: UUID

    @Environment(\.dismiss) private var dismiss
    @State private var content = ""
    @State private var errorAlert: UserFacingAlert?

    var body: some View {
        NavigationStack {
            TextEditor(text: $content)
                .font(.body)
                .padding()
                .navigationTitle("新增")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("加入") { add() }
                            .disabled(content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
        }
        .noteErrorAlert($errorAlert)
    }

    private func add() {
        let value = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        do {
            _ = try store.createIdea(
                content: value,
                attachmentInputs: [],
                groupID: groupID
            )
            dismiss()
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            errorAlert = UserFacingAlert.local(error: error)
        }
    }
}
