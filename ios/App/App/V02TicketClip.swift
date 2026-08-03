import SwiftUI

/// 固定在小票册中的空间锚点。纸张始终从这里出现，避免根页退化为普通卡片列表。
struct V02TicketClip: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(NoteTheme.background.opacity(0.74))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(Color.white.opacity(0.8), lineWidth: 1)
                }
                .shadow(color: NoteTheme.ink.opacity(0.08), radius: 14, y: 8)

            HStack(spacing: 0) {
                clipHandle
                Rectangle()
                    .fill(NoteTheme.paper.opacity(0.26))
                    .frame(maxWidth: .infinity, maxHeight: 18)
                clipHandle
            }
            .padding(.horizontal, 8)

            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(NoteTheme.ink.opacity(0.82))
                .frame(width: 136, height: 7)
                .overlay(alignment: .trailing) {
                    HStack(spacing: 5) {
                        Circle().fill(Color.white.opacity(0.82)).frame(width: 3, height: 3)
                        Circle().fill(Color.white.opacity(0.48)).frame(width: 3, height: 3)
                    }
                    .padding(.trailing, 9)
                }
        }
        .frame(height: 42)
        .accessibilityHidden(true)
    }

    private var clipHandle: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Color.white.opacity(0.78))
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(NoteTheme.secondaryInk.opacity(0.18), lineWidth: 1)
            }
            .frame(width: 30, height: 22)
    }
}
