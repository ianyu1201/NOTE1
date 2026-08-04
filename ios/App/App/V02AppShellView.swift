import SwiftUI
import UniformTypeIdentifiers
import UIKit
import PhotosUI

enum V02PrimaryPage: String, CaseIterable, Identifiable {
    case inspirations = "灵感"
    case cards = "卡片预览"
    case collections = "构思集"
    case receipts = "小票册"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .inspirations: "sparkles"
        case .cards: "rectangle.on.rectangle"
        case .collections: "folder"
        case .receipts: "ticket"
        }
    }
}

struct V02AppShellView: View {
    @ObservedObject var store: V02Store
    @State private var page: V02PrimaryPage = .inspirations
    @State private var isPresentingComposer = false
    @State private var isPresentingSettings = false
    @State private var isPresentingTrash = false
    @State private var isPresentingSearch = false
    @State private var isPresentingHistory = false
    @State private var isManagingSelection = false
    @State private var error: UserFacingAlert?
    @State private var generatedReceipt: V02Receipt?
    @State private var presentedReceipt: V02Receipt?
    @State private var isCollectionWorkbenchPresented = false
    @State private var isRequestingNewCollection = false
    @State private var isChildEditorPresented = false
    @State private var isCardOverlayPresented = false
    @State private var isReceiptOverlayPresented = false

    var body: some View {
        ZStack {
            NoteTheme.background.ignoresSafeArea()
            GeometryReader { proxy in
                TabView(selection: $page) {
                    ForEach(V02PrimaryPage.allCases) { destination in
                        pageContent(for: destination)
                            .accessibilityHidden(
                                generatedReceipt != nil
                                    || presentedReceipt != nil
                                    || isChildEditorPresented
                            )
                            .tabItem {
                                Label(destination.rawValue, systemImage: destination.symbol)
                                    .accessibilityHidden(
                                        generatedReceipt != nil
                                            || presentedReceipt != nil
                                            || isChildEditorPresented
                                    )
                            }
                            .tag(destination)
                            .accessibilityIdentifier("v02.primary.\(destination.rawValue)")
                    }
                }
                    .toolbar(isChildEditorPresented ? .hidden : .visible, for: .tabBar)
                    // The receipt-generation layer is a focused modal state
                    // owned by the shell. Keep the underlying tabs out of the
                    // accessibility tree while that layer is visible; the
                    // tabs remain visually present behind the settled paper
                    // but must not compete with its actions in VoiceOver.
                    .accessibilityHidden(
                        generatedReceipt != nil
                            || presentedReceipt != nil
                            || isChildEditorPresented
                    )
                    .simultaneousGesture(primaryPageEdgeGesture(width: proxy.size.width))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let generatedReceipt {
                V02ReceiptGenerationView(
                    store: store,
                    receipt: generatedReceipt,
                    onView: { receipt in
                        presentedReceipt = receipt
                        self.generatedReceipt = nil
                    },
                    onReturn: { self.generatedReceipt = nil },
                    onUndo: {
                        do {
                            try store.undoEndRound(generatedReceipt.id)
                            self.generatedReceipt = nil
                        } catch let caughtError { self.error = UserFacingAlert(error: caughtError) }
                    }
                )
                .padding(.bottom, V02ReceiptGenerationLayoutPolicy.bottomPadding(navigationHeight: NoteTheme.navigationHeight))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .transition(.opacity)
                .zIndex(V02ReceiptGenerationLayoutPolicy.generationZIndex)
            }
        }
        .background {
            V02ModalAccessibilityIsolation(
                hidesRoot: presentedReceipt != nil
                    || isChildEditorPresented
                    || isReceiptOverlayPresented,
                hidesTabBar: generatedReceipt != nil
                    || presentedReceipt != nil
                    || isChildEditorPresented
                    || isCollectionWorkbenchPresented
                    || isReceiptOverlayPresented
            )
            .frame(width: 0, height: 0)
        }
        .overlay(alignment: .bottomTrailing) {
            if V02NavigationLayoutPolicy.showsFloatingComposer(
                on: page,
                isOverlayPresented: isPresentingComposer
                    || isPresentingSearch
                    || isPresentingHistory
                    || isPresentingSettings
                    || isPresentingTrash
                    || isManagingSelection
                    || isCollectionWorkbenchPresented
                    || isChildEditorPresented
                    || isCardOverlayPresented
                    || generatedReceipt != nil
                    || presentedReceipt != nil
            ) {
                V02FloatingComposerButton(
                    action: {
                        if page == .collections {
                            isRequestingNewCollection = true
                        } else {
                            isPresentingComposer = true
                        }
                    },
                    label: V02NavigationLayoutPolicy.composerLabel(for: page)
                )
                    .padding(.trailing, NoteTheme.horizontalPadding)
                    .padding(.bottom, V02NavigationLayoutPolicy.floatingComposerBottomPadding)
                    .zIndex(V02ReceiptGenerationLayoutPolicy.composerZIndex)
            }
        }
        .sheet(isPresented: $isPresentingComposer) {
            V02ComposerView(store: store) { error in
                self.error = UserFacingAlert(error: error)
            }
        }
        .sheet(isPresented: $isPresentingSettings) {
            V02SettingsView(store: store)
        }
        .sheet(isPresented: $isPresentingTrash) {
            V02TrashView(store: store)
        }
        .sheet(isPresented: $isPresentingSearch) {
            V02SearchView(store: store)
        }
        .sheet(isPresented: $isPresentingHistory) {
            V02CollectionHistoryView(store: store) { error in
                self.error = UserFacingAlert(error: error)
            }
        }
        .sheet(item: $presentedReceipt) { receipt in
            V02ReceiptDetailView(store: store, receipt: receipt)
        }
        .tint(NoteTheme.ink)
        .noteErrorAlert($error)
        .onChange(of: page) { _, newPage in
            // Selection is local to the page that owns it; never carry a
            // hidden selection mode into another primary destination.
            isManagingSelection = false
            if newPage != .collections {
                isCollectionWorkbenchPresented = false
            }
        }
    }

    @ViewBuilder
    private func pageContent(for destination: V02PrimaryPage) -> some View {
        switch destination {
        case .inspirations:
            V02InspirationListView(
                store: store,
                isSelecting: $isManagingSelection,
                showSettings: { isPresentingSettings = true },
                showTrash: { isPresentingTrash = true },
                showSearch: { isPresentingSearch = true },
                onEditingChange: { isChildEditorPresented = $0 }
            ) { error in
                self.error = UserFacingAlert(error: error)
            }
        case .cards:
            V02CardPreviewView(
                store: store,
                onBack: { page = .inspirations },
                onHistory: { isPresentingHistory = true },
                reportError: { error in
                self.error = UserFacingAlert(error: error)
                },
                onEditingChange: { isChildEditorPresented = $0 },
                onOverlayChange: { isCardOverlayPresented = $0 }
            )
        case .collections:
            V02CollectionListView(
                store: store,
                isWorkbenchPresented: $isCollectionWorkbenchPresented,
                isRequestingNewCollection: $isRequestingNewCollection,
                isGenerationPresented: generatedReceipt != nil,
                showGeneration: { receipt in generatedReceipt = receipt }
            ) { error in
                self.error = UserFacingAlert(error: error)
            }
        case .receipts:
            V02ReceiptBookView(
                store: store,
                isSelecting: $isManagingSelection,
                onOverlayChange: { isReceiptOverlayPresented = $0 }
            )
        }
    }

    private func primaryPageEdgeGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 18)
            .onEnded { value in
                let startsAtLeadingEdge = value.startLocation.x <= 24
                let startsAtTrailingEdge = value.startLocation.x >= width - 24
                guard abs(value.translation.width) > abs(value.translation.height),
                      abs(value.translation.width) >= 72 else { return }
                if startsAtTrailingEdge, value.translation.width < 0 {
                    page = page.after
                } else if startsAtLeadingEdge, value.translation.width > 0 {
                    page = page.before
                }
            }
    }
}

/// SwiftUI's `accessibilityHidden` does not consistently propagate through
/// the UIKit presentation host used by a `TabView` and `fullScreenCover`.
/// When a full-screen child or receipt layer is active, hide the underlying
/// shell and its tab bar descendants from VoiceOver without changing the
/// visual presentation.
private struct V02ModalAccessibilityIsolation: UIViewRepresentable {
    let hidesRoot: Bool
    let hidesTabBar: Bool

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        let apply = {
            guard let root = uiView.window?.rootViewController?.view else { return }
            root.accessibilityElementsHidden = hidesRoot
            root.v02ForEachDescendant { view in
                guard let tabBar = view as? UITabBar else { return }
                tabBar.accessibilityElementsHidden = hidesTabBar
            }
        }
        apply()
        DispatchQueue.main.async(execute: apply)
    }
}

private extension UIView {
    func v02ForEachDescendant(_ visit: (UIView) -> Void) {
        visit(self)
        subviews.forEach { $0.v02ForEachDescendant(visit) }
    }
}

private extension V02PrimaryPage {
    var before: V02PrimaryPage {
        switch self {
        case .inspirations: self
        case .cards: .inspirations
        case .collections: .cards
        case .receipts: .collections
        }
    }

    var after: V02PrimaryPage {
        switch self {
        case .inspirations: .cards
        case .cards: .collections
        case .collections: .receipts
        case .receipts: self
        }
    }
}
