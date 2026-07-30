import SwiftUI

struct HistoryRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let item: ReviewItem

    var body: some View {
        (
            dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(spacing: 14))
        ) {
            Image(systemName: item.symbolName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(NoteTheme.ink)
                .frame(width: 32, height: 32)
                .background(Color.white.opacity(0.34), in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.68), lineWidth: 1)
                }
            VStack(alignment: .leading, spacing: 5) {
                Text(item.title)
                    .noteFont(
                        size: 16,
                        weight: .semibold,
                        relativeTo: .body
                    )
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                if let completedAt = item.completedAt {
                    Text("完成于 \(NoteDateFormatter.display(completedAt))")
                        .font(.caption)
                        .foregroundStyle(NoteTheme.secondaryInk)
                } else {
                    Text("更新于 \(NoteDateFormatter.display(item.activityAt))")
                        .font(.caption)
                        .foregroundStyle(NoteTheme.secondaryInk)
                }
            }
            if !dynamicTypeSize.isAccessibilitySize {
                Spacer()
            }
            Text(item.status == .completed ? "已完成" : "未完成")
                .font(.caption.weight(.semibold))
                .foregroundStyle(
                    item.status == .completed
                        ? NoteTheme.secondaryInk
                        : NoteTheme.accent
                )
        }
        .padding(.vertical, 8)
    }
}

extension View {
    @ViewBuilder
    func `if`<Content: View>(
        _ condition: Bool,
        transform: (Self) -> Content
    ) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

extension ReviewItem {
    var title: String {
        switch self {
        case .idea(let idea): return idea.content.isEmpty ? "未命名想法" : idea.content
        case .group(let group): return group.name
        }
    }

    var symbolName: String {
        switch self {
        case .idea: return "note.text"
        case .group: return "rectangle.stack.fill"
        }
    }
}
