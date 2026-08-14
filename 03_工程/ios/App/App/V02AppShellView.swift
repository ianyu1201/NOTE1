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

enum V02AppSheet: Identifiable {
    case composer
    case settings
    case trash
    case search
    case history
    case receipt(V02Receipt)

    var id: String {
        switch self {
        case .composer: "composer"
        case .settings: "settings"
        case .trash: "trash"
        case .search: "search"
        case .history: "history"
        case .receipt(let r): "receipt.\(r.id)"
        }
    }
}

struct V02AppShellView: View {
    @ObservedObject var store: V02Store
    @State private var page: V02PrimaryPage = .inspirations
    @State private var sheet: V02AppSheet?
    @State private var error: UserFacingAlert?
    @State private var generatedReceipt: V02Receipt?
    @State private var isCollectionWorkbenchPresented = false
    @State private var isRequestingNewCollection = false
    @State private var isChildEditorPresented = false
    @State private var isManagingSelection = false
    @State private var isCardOverlayPresented = false
    @State private var isReceiptOverlayPresented = false

    private var isPresentedRootModal: Bool {
        sheet != nil
            || isChildEditorPresented
            || isReceiptOverlayPresented
    }

    private var shouldHidePrimaryContentAccessibility: Bool {
        generatedReceipt != nil || isPresentedRootModal
    }

    private var shouldHideTabBarAccessibility: Bool {
        shouldHidePrimaryContentAccessibility || isCollectionWorkbenchPresented
    }

    private var shouldHideFloatingComposer: Bool {
        sheet != nil
            || isManagingSelection
            || isCollectionWorkbenchPresented
            || isChildEditorPresented
            || isCardOverlayPresented
            || generatedReceipt != nil
    }

    var body: some View {
        ZStack {
            NoteTheme.background.ignoresSafeArea()
            GeometryReader { proxy in
                TabView(selection: $page) {
                    ForEach(V02PrimaryPage.allCases) { destination in
                        pageContent(for: destination)
                            .accessibilityHidden(
                                shouldHidePrimaryContentAccessibility
                            )
                            .tabItem {
                                Label(destination.rawValue, systemImage: destination.symbol)
                                    .accessibilityHidden(
                                        shouldHidePrimaryContentAccessibility
                                    )
                            }
                            .tag(destination)
                            .accessibilityIdentifier("v02.primary.\(destination.rawValue)")
                    }
                }
                    .toolbar(isChildEditorPresented ? .hidden : .visible, for: .tabBar)
                    .accessibilityHidden(
                        shouldHidePrimaryContentAccessibility
                    )
                    .simultaneousGesture(primaryPageEdgeGesture(width: proxy.size.width))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if let generatedReceipt {
                V02ReceiptGenerationView(
                    store: store,
                    receipt: generatedReceipt,
                    onView: { receipt in
                        sheet = .receipt(receipt)
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
                hidesRoot: isPresentedRootModal,
                hidesTabBar: shouldHideTabBarAccessibility
            )
            .frame(width: 0, height: 0)
        }
        .overlay(alignment: .bottomTrailing) {
            if V02NavigationLayoutPolicy.showsFloatingComposer(
                on: page,
                isOverlayPresented: shouldHideFloatingComposer || generatedReceipt != nil
            ) {
                V02FloatingComposerButton(
                    action: { sheet = .composer },
                    label: V02NavigationLayoutPolicy.composerLabel(for: page)
                )
                    .padding(.trailing, NoteTheme.horizontalPadding)
                    .padding(.bottom, V02NavigationLayoutPolicy.floatingComposerBottomPadding)
                    .zIndex(V02ReceiptGenerationLayoutPolicy.composerZIndex)
            }
        }
        .sheet(item: $sheet) { item in
            switch item {
            case .composer:
                V02ComposerView(store: store) { error in
                    self.error = UserFacingAlert(error: error)
                }
            case .settings:
                V02SettingsView(store: store)
            case .trash:
                V02TrashView(store: store)
            case .search:
                V02SearchView(store: store)
            case .history:
                V02CollectionHistoryView(store: store) { error in
                    self.error = UserFacingAlert(error: error)
                }
            case .receipt(let receipt):
                V02ReceiptDetailView(store: store, receipt: receipt)
            }
        }
        .tint(NoteTheme.ink)
        .noteErrorAlert($error)
        .onChange(of: page) { _, newPage in
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
                showSettings: { sheet = .settings },
                showTrash: { sheet = .trash },
                showSearch: { sheet = .search },
                showHistory: { sheet = .history },
                onEditingChange: { isChildEditorPresented = $0 }
            ) { error in
                self.error = UserFacingAlert(error: error)
            }
        case .cards:
            V02CardPreviewView(
                store: store,
                showSettings: { sheet = .settings },
                showTrash: { sheet = .trash },
                showHistory: { sheet = .history },
                showSearch: { sheet = .search },
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
                showSettings: { sheet = .settings },
                showTrash: { sheet = .trash },
                showSearch: { sheet = .search },
                showHistory: { sheet = .history },
                showGeneration: { receipt in generatedReceipt = receipt }
            ) { error in
                self.error = UserFacingAlert(error: error)
            }
        case .receipts:
            V02ReceiptBookView(
                store: store,
                isSelecting: $isManagingSelection,
                showSettings: { sheet = .settings },
                showTrash: { sheet = .trash },
                showHistory: { sheet = .history },
                showSearch: { sheet = .search },
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
