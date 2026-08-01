import SwiftUI

extension ReviewView {
    var completionCueProgress: Double {
        let distance = max(-dragOffset.width, 0)
        return min(max((distance - 76) / 84, 0), 1)
    }

    func reviewGesture(
        for item: ReviewItem,
        containerSize: CGSize
    ) -> some Gesture {
        DragGesture(
            minimumDistance: 0,
            coordinateSpace: .named("reviewCanvas")
        )
            .onChanged { value in
                guard !isCompleting else { return }

                if dragAxis == nil {
                    dragAxis = ReviewGestureClassifier.axis(
                        for: value.translation
                    )
                    guard dragAxis != nil else { return }
                }

                switch dragAxis {
                case .horizontal:
                    let horizontal = value.translation.width < 0
                        ? value.translation.width
                        : value.translation.width * 0.18
                    dragOffset = CGSize(
                        width: horizontal,
                        height: value.translation.height * 0.06
                    )
                case .vertical:
                    dragOffset = CGSize(
                        width: value.translation.width * 0.04,
                        height: value.translation.height
                    )
                case nil:
                    break
                }
            }
            .onEnded { value in
                guard !isCompleting else { return }

                if ReviewGestureClassifier.shouldComplete(
                    axis: dragAxis,
                    translation: value.translation,
                    predictedEndTranslation: value.predictedEndTranslation
                ) {
                    completeCurrent(
                        direction: -1,
                        width: containerSize.width
                    )
                } else if ReviewGestureClassifier.shouldPage(
                    axis: dragAxis,
                    translation: value.translation,
                    predictedEndTranslation: value.predictedEndTranslation
                ) {
                    page(
                        direction: value.predictedEndTranslation.height < 0 ? 1 : -1,
                        height: containerSize.height
                    )
                } else {
                    settle()
                }
            }
    }

    func groupButtonGesture(for idea: Idea) -> some Gesture {
        DragGesture(
            minimumDistance: 0,
            coordinateSpace: .named("reviewCanvas")
        )
        .updating($groupButtonPressed) { _, pressed, _ in
            pressed = true
        }
        .onChanged { value in
            guard !isCompleting else { return }
            let distance = hypot(
                value.translation.width,
                value.translation.height
            )

            if groupingIdeaID == nil, distance >= 8 {
                beginGrouping(ideaID: idea.id)
            }

            guard groupingIdeaID == idea.id else { return }
            updateGroupTarget(at: value.location)
        }
        .onEnded { value in
            guard !isCompleting else { return }

            if groupingIdeaID == idea.id {
                updateGroupTarget(at: value.location)
                finishGrouping(ideaID: idea.id)
            } else {
                showGroupPicker = true
            }
        }
    }

    func beginGrouping(ideaID: UUID) {
        guard groupingIdeaID == nil else { return }
        groupingIdeaID = ideaID
        suppressCardGesture = true
        dragOffset = .zero
        dragAxis = nil
        withAnimation(
            reduceMotion
                ? nil
                : .spring(response: 0.3, dampingFraction: 0.8)
        ) {
            groupMenuExpanded = true
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    func updateGroupTarget(at location: CGPoint) {
        if !groupMenuExpanded,
           groupButtonFrame.insetBy(dx: -54, dy: -54).contains(location) {
            withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.78)) {
                groupMenuExpanded = true
            }
        }
        guard groupMenuExpanded else { return }

        let previousGroupID = hoveredGroupID
        let previousNew = hoveringNew

        let groupFrames = Dictionary(
            uniqueKeysWithValues: quickGroups.compactMap { group in
                groupTargetFrames[group.id.uuidString].map { (group.id, $0) }
            }
        )
        let target = ReviewGroupDropClassifier.target(
            at: location,
            groupFrames: groupFrames,
            newFrame: groupTargetFrames["new"]
        )

        switch target {
        case .group(let groupID):
            hoveredGroupID = groupID
            hoveringNew = false
        case .new:
            hoveredGroupID = nil
            hoveringNew = true
        case nil:
            hoveredGroupID = nil
            hoveringNew = false
        }

        if previousGroupID != hoveredGroupID || previousNew != hoveringNew {
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    func finishGrouping(ideaID: UUID) {
        let targetGroupID = hoveredGroupID

        if let targetGroupID {
            do {
                try store.assignIdea(ideaID, to: targetGroupID)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                present(error)
            }
        } else if hoveringNew {
            showGroupPicker = true
        }

        resetGroupingState()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            suppressCardGesture = false
        }
    }

    func resetGroupingState() {
        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.82)) {
            groupingIdeaID = nil
            groupMenuExpanded = false
            hoveredGroupID = nil
            hoveringNew = false
            dragOffset = .zero
            dragAxis = nil
        }
    }

    func settle() {
        withAnimation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.76)) {
            dragOffset = .zero
            dragAxis = nil
        }
    }

    func page(direction: Int, height: CGFloat) {
        dragAxis = nil
        let nextIndex = index + direction
        guard items.indices.contains(nextIndex) else {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            settle()
            return
        }

        let change = {
            index = nextIndex
            dragOffset = CGSize(width: 0, height: direction > 0 ? height : -height)
            withAnimation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.84)) {
                dragOffset = .zero
            }
            UISelectionFeedbackGenerator().selectionChanged()
        }

        guard !reduceMotion else {
            change()
            return
        }
        withAnimation(.easeIn(duration: 0.16)) {
            dragOffset.height = direction > 0 ? -height : height
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: change)
    }

    func completeCurrent(direction: CGFloat, width: CGFloat) {
        guard let item = currentItem, !isCompleting else { return }
        isCompleting = true

        let finish = {
            do {
                cardPresented = false
                try store.complete(item)
                dragOffset = .zero
                dragAxis = nil
                index = min(index, max(0, items.count - 1))
                showUndo(for: item)
                UINotificationFeedbackGenerator().notificationOccurred(.success)

                if currentItem != nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                        withAnimation(
                            reduceMotion
                                ? .easeOut(duration: 0.12)
                                : .spring(response: 0.48, dampingFraction: 0.82)
                        ) {
                            cardPresented = true
                        }
                    }
                    DispatchQueue.main.asyncAfter(
                        deadline: .now() + (reduceMotion ? 0.16 : 0.4)
                    ) {
                        isCompleting = false
                    }
                } else {
                    cardPresented = true
                    isCompleting = false
                }
            } catch {
                dragOffset = .zero
                cardPresented = true
                isCompleting = false
                present(error)
            }
        }
        guard !reduceMotion else {
            finish()
            return
        }
        withAnimation(.easeIn(duration: 0.28)) {
            dragOffset.width = direction * (width + 120)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28, execute: finish)
    }

    func showUndo(for item: ReviewItem) {
        undoDismissTask?.cancel()
        withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) {
            undoItem = item
        }

        let task = DispatchWorkItem {
            guard undoItem?.id == item.id else { return }
            withAnimation(.easeOut(duration: 0.22)) {
                undoItem = nil
            }
        }
        undoDismissTask = task
        DispatchQueue.main.asyncAfter(
            deadline: .now() + ReviewInteractionTiming.undoBannerDuration,
            execute: task
        )
    }

    func undoCompletion() {
        guard let item = undoItem else { return }
        undoDismissTask?.cancel()
        do {
            try store.restore(item)
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                index = 0
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                guard undoItem?.id == item.id else { return }
                withAnimation(.easeOut(duration: 0.18)) {
                    undoItem = nil
                }
            }
        } catch {
            present(error)
        }
    }

    func open(_ item: ReviewItem) {
        switch item {
        case .idea(let idea): onOpenIdea(idea.id)
        case .group(let group): onOpenGroup(group.id)
        }
    }

    func present(_ error: Error) {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        errorAlert = UserFacingAlert.local(error: error)
    }
}
