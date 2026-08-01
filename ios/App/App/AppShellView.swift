import SwiftUI

enum AppRoute: Hashable {
    case home
    case review
    case history
    case editor(UUID)
    case group(UUID)
}

struct AppShellView: View {
    @ObservedObject var store: NoteStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @State private var route: AppRoute = .home
    @State private var routeHistory: [AppRoute] = []
    @State private var isNavigatingBack = false
    @State private var isNavigationLocked = false
    @State private var contentVisible = false
    @State private var edgeBackOffset: CGFloat = 0
    @State private var errorAlert: UserFacingAlert?
    @State private var selectedReviewItemID = ReviewPositionPreference.load()
    @State private var externalDraft: String?

    init(store: NoteStore) {
        self.store = store
    }

    var body: some View {
        ZStack {
            NoteTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                SharedTopBar(
                    onBack: route == .home ? nil : { navigateBack() },
                    historySelected: route == .history,
                    onHistory: {
                        route == .history ? navigateBack() : navigate(to: .history)
                    }
                )
                .padding(.horizontal, NoteTheme.horizontalPadding)
                .padding(.top, 4)
                .zIndex(2)

                ZStack {
                    screen
                        .id(route)
                        .transition(screenTransition)
                        .offset(x: supportsEdgeBack ? edgeBackOffset : 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea(
                    .container,
                    edges: usesSharedBottomSlot ? .bottom : []
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(contentVisible ? 1 : 0)
            .scaleEffect(contentVisible ? 1 : 1.012)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tint(NoteTheme.ink)
        .foregroundStyle(NoteTheme.ink)
        .overlay(alignment: .leading) {
            if supportsEdgeBack {
                Color.clear
                    .frame(width: EdgeBackGestureClassifier.activationWidth)
                    .contentShape(Rectangle())
                    .gesture(edgeBackGesture)
                    .accessibilityHidden(true)
            }
        }
        .onAppear {
            playLaunchTransition()
            presentStartupErrorIfNeeded()
            handlePendingShortcutDraft()
        }
        .onChange(of: store.lastPersistenceError) { _, message in
            guard !store.isReadOnlyBecausePersistenceFailed,
                  let message else { return }
            errorAlert = UserFacingAlert(
                message: "本机数据没有保存成功：\(message)"
            )
        }
        .onChange(of: selectedReviewItemID) { _, itemID in
            ReviewPositionPreference.save(itemID)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            handlePendingShortcutDraft()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: AppShortcutDraftStore.didSaveNotification
            )
        ) { _ in
            handlePendingShortcutDraft()
        }
        .noteErrorAlert($errorAlert)
    }

    private var usesSharedBottomSlot: Bool {
        route == .home || route == .review
    }

    private var supportsEdgeBack: Bool {
        route == .review || route == .history
    }

    @ViewBuilder
    private var screen: some View {
        switch route {
        case .home:
            HomeView(
                store: store,
                externalDraft: $externalDraft,
                onReview: { navigate(to: .review) },
                onOpenIdea: { navigate(to: .editor($0)) }
            )
        case .review:
            ReviewView(
                store: store,
                selectedItemID: $selectedReviewItemID,
                onOpenIdea: { navigate(to: .editor($0)) },
                onOpenGroup: { navigate(to: .group($0)) }
            )
        case .history:
            HistoryView(
                store: store,
                onOpenIdea: { navigate(to: .editor($0)) },
                onOpenGroup: { navigate(to: .group($0)) }
            )
        case .editor(let id):
            EditorView(store: store, ideaID: id)
        case .group(let id):
            IdeaGroupView(
                store: store,
                groupID: id,
                onOpenIdea: { navigate(to: .editor($0)) }
            )
        }
    }

    private var screenTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let movingForward = !isNavigatingBack
        return .asymmetric(
            insertion: .move(edge: movingForward ? .trailing : .leading)
                .combined(with: .opacity),
            removal: .move(edge: movingForward ? .leading : .trailing)
                .combined(with: .opacity)
        )
    }

    private func navigate(to destination: AppRoute) {
        guard destination != route, !isNavigationLocked else { return }
        lockNavigation()
        routeHistory.append(route)
        isNavigatingBack = false
        withAnimation(reduceMotion ? .linear(duration: 0.12) : .spring(response: 0.42, dampingFraction: 0.86)) {
            route = destination
        }
    }

    private func navigateBack() {
        guard !isNavigationLocked else { return }
        let destination = routeHistory.popLast() ?? .home
        guard destination != route else { return }
        lockNavigation()
        isNavigatingBack = true
        withAnimation(reduceMotion ? .linear(duration: 0.12) : .spring(response: 0.42, dampingFraction: 0.86)) {
            route = destination
        }
    }

    private var edgeBackGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard value.translation.width > 0,
                      abs(value.translation.width) > abs(value.translation.height)
                else { return }
                edgeBackOffset = min(value.translation.width, 120)
            }
            .onEnded { value in
                let shouldNavigate = EdgeBackGestureClassifier.shouldNavigateBack(
                    startX: value.startLocation.x,
                    translation: value.translation,
                    predictedEndTranslation: value.predictedEndTranslation
                )
                edgeBackOffset = 0
                if shouldNavigate {
                    navigateBack()
                } else {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        edgeBackOffset = 0
                    }
                }
            }
    }

    private func lockNavigation() {
        isNavigationLocked = true
        let delay = reduceMotion ? 0.14 : 0.46
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            isNavigationLocked = false
        }
    }

    private func playLaunchTransition() {
        guard !contentVisible else { return }

        if reduceMotion {
            contentVisible = true
            return
        }

        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) {
                contentVisible = true
            }
        }
    }

    private func presentStartupErrorIfNeeded() {
        guard store.isReadOnlyBecausePersistenceFailed else { return }
        errorAlert = UserFacingAlert(
            message: "NOTE1 无法读取原有本机数据。为保护这些记录，本次已暂停写入。请不要删除 App，可先保留数据后再处理。"
        )
    }

    private func handlePendingShortcutDraft() {
        guard let text = AppShortcutDraftStore.consume() else { return }
        externalDraft = text
        guard route != .home else { return }
        routeHistory.removeAll()
        isNavigatingBack = true
        withAnimation(
            reduceMotion
                ? .linear(duration: 0.12)
                : .spring(response: 0.42, dampingFraction: 0.86)
        ) {
            route = .home
        }
    }
}

enum ReviewPositionPreference {
    private static let key = "note1.review.last-item-id"

    static func load(defaults: UserDefaults = .standard) -> UUID? {
        defaults.string(forKey: key).flatMap(UUID.init(uuidString:))
    }

    static func save(
        _ itemID: UUID?,
        defaults: UserDefaults = .standard
    ) {
        if let itemID {
            defaults.set(itemID.uuidString, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}

enum EdgeBackGestureClassifier {
    static let activationWidth: CGFloat = 30

    static func shouldNavigateBack(
        startX: CGFloat,
        translation: CGSize,
        predictedEndTranslation: CGSize
    ) -> Bool {
        guard startX <= activationWidth, translation.width > 0 else {
            return false
        }

        let horizontal = max(translation.width, predictedEndTranslation.width)
        let vertical = max(
            abs(translation.height),
            abs(predictedEndTranslation.height)
        )
        return horizontal >= 84 && horizontal >= vertical * 1.25
    }
}
