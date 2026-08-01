import SwiftUI

struct HomeView: View {
    @ObservedObject var store: NoteStore
    @Binding var externalDraft: String?
    let onReview: () -> Void
    let onOpenIdea: (UUID) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var composerDraft = HomeComposerDraft()
    @State private var showComposer = false

    var body: some View {
        VStack(spacing: 0) {
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
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            bottomActions
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, NoteTheme.horizontalPadding)
        .sheet(isPresented: $showComposer) {
            HomeComposerView(
                store: store,
                draft: $composerDraft
            )
            .presentationDetents([
                dynamicTypeSize.isAccessibilitySize
                    ? .medium
                    : .height(310)
            ])
        }
        .onAppear {
            applyExternalDraft()
        }
        .onChange(of: externalDraft) { _, _ in
            applyExternalDraft()
        }
    }

    private var bottomActions: some View {
        ZStack {
            RoundGlassButton(
                systemName: "plus",
                label: "记录新灵感",
                size: 72,
                iconSize: 24,
                action: {
                    showComposer = true
                }
            )

            HStack {
                Spacer()
                RoundGlassButton(
                    systemName: "square.on.square",
                    label: "进入卡片回看",
                    size: 60,
                    iconSize: 19,
                    action: onReview
                )
            }
        }
        .frame(maxWidth: .infinity, minHeight: 76)
    }

    @ViewBuilder
    private var recentIdeas: some View {
        VStack(spacing: 0) {
            ForEach(recentIdeasForDisplay) { idea in
                Button {
                    onOpenIdea(idea.id)
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(
                                idea.content.isEmpty
                                    ? "未命名想法"
                                    : idea.content
                            )
                            .noteFont(
                                size: 14,
                                weight: .semibold,
                                relativeTo: .subheadline
                            )
                            .lineLimit(
                                dynamicTypeSize.isAccessibilitySize ? nil : 1
                            )
                            .multilineTextAlignment(.leading)

                            Text(
                                NoteDateFormatter.display(idea.activityAt)
                            )
                            .noteFont(size: 11, relativeTo: .caption)
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

                if idea.id != recentIdeasForDisplay.last?.id {
                    Divider()
                        .overlay(NoteTheme.divider)
                        .padding(.horizontal, 16)
                }
            }
        }
        .noteGlass(cornerRadius: 22, strokeOpacity: 0.55)
        .animation(
            reduceMotion
                ? nil
                : .spring(response: 0.44, dampingFraction: 0.82),
            value: recentIdeasForDisplay.map(\.id)
        )
    }

    private var recentIdeasForDisplay: [Idea] {
        Array(
            store.recentActiveIdeas.prefix(
                dynamicTypeSize.isAccessibilitySize ? 1 : 5
            )
        )
    }

    private func applyExternalDraft() {
        guard let incoming = externalDraft?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !incoming.isEmpty else {
            return
        }

        composerDraft.text = HomeComposerDraft.appending(
            incoming,
            to: composerDraft.text
        )
        externalDraft = nil
        showComposer = true
    }
}
