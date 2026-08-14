import SwiftUI

/// Legacy source-compatibility placeholder. Receipt paper now begins at its
/// own top edge and no longer renders a clip, clamp, strip, or fastener.
@available(*, deprecated, message: "Receipt paper no longer uses a ticket clip.")
struct V02TicketClip: View {
    var body: some View {
        EmptyView()
    }
}
