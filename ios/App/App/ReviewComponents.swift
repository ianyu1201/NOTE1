import SwiftUI

struct GroupDropTray: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
                .noteFont(
                    size: 11,
                    weight: .semibold,
                    relativeTo: .caption
                )
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
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

struct ReviewCardView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let item: ReviewItem
    let ideaCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer(minLength: 0)

            switch item {
            case .idea(let idea):
                Text(NoteDateFormatter.display(idea.createdAt))
                    .noteFont(
                        size: 14,
                        weight: .medium,
                        relativeTo: .subheadline
                    )
                    .foregroundStyle(NoteTheme.secondaryInk)
                Text(idea.content.isEmpty ? "未命名想法" : idea.content)
                    .noteFont(
                        size: 20,
                        design: .rounded,
                        relativeTo: .title3
                    )
                    .lineSpacing(6)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 10)
            case .group(let group):
                Label("灵感组", systemImage: "rectangle.stack.fill")
                    .noteFont(
                        size: 14,
                        weight: .semibold,
                        relativeTo: .subheadline
                    )
                    .foregroundStyle(NoteTheme.secondaryInk)
                Text(group.name)
                    .noteFont(
                        size: 31,
                        weight: .bold,
                        design: .rounded,
                        relativeTo: .largeTitle
                    )
                Text("\(ideaCount) 条想法")
                    .noteFont(
                        size: 15,
                        weight: .medium,
                        relativeTo: .subheadline
                    )
                    .foregroundStyle(NoteTheme.secondaryInk)
            }

            Spacer(minLength: 0)

            HStack {
                Label("上下切换", systemImage: "arrow.up.arrow.down")
                Spacer()
                Label("左滑完成", systemImage: "arrow.left")
            }
            .noteFont(
                size: 12,
                weight: .medium,
                relativeTo: .caption
            )
            .foregroundStyle(NoteTheme.secondaryInk)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .noteGlass(cornerRadius: 38)
    }
}

struct CompletionUndoBanner: View {
    let title: String
    let onUndo: () -> Void

    var body: some View {
        Button(action: onUndo) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(NoteTheme.accent)
                Text("已完成")
                    .noteFont(
                        size: 14,
                        weight: .semibold,
                        relativeTo: .subheadline
                    )
                Text(title)
                    .noteFont(size: 13, relativeTo: .footnote)
                    .foregroundStyle(NoteTheme.secondaryInk)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("撤回")
                    .noteFont(
                        size: 14,
                        weight: .bold,
                        relativeTo: .subheadline
                    )
                    .foregroundStyle(NoteTheme.accent)
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 54)
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleButtonStyle())
        .noteGlass(cornerRadius: 27)
        .accessibilityLabel("撤回完成，\(title)")
        .accessibilityIdentifier("review.completion.undo")
    }
}
