import SwiftUI

/// 固定在小票册中的空间锚点。纸张始终从这里出现，避免根页退化为普通卡片列表。
struct V02TicketClip: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(NoteTheme.paperSurface)
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(NoteTheme.paperBorder, lineWidth: 1)
                }
                .shadow(color: NoteTheme.ink.opacity(0.11), radius: 16, y: 9)

            HStack(spacing: 0) {
                clipHandle
                Rectangle()
                    .fill(NoteTheme.receiptPaper.opacity(0.46))
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
            .background(NoteTheme.receiptPaper.opacity(0.7), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(NoteTheme.secondaryInk.opacity(0.18), lineWidth: 1)
            }
            .frame(width: 30, height: 22)
    }
}
