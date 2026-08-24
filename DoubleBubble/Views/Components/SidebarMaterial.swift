import SwiftUI
import AppKit

/// The real sidebar material, for places that aren't inside a `List`.
///
/// `NavigationSplitView`'s sidebar gets this for free. The settings window's
/// source list is a hand-built `VStack`, which does not — it was painting a
/// flat colour and reading as a coloured rectangle rather than as a sidebar.
/// Going through `NSVisualEffectView` also means Reduce Transparency and
/// Increase Contrast are handled by the system instead of being re-implemented
/// badly.
struct SidebarMaterial: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

extension View {
    /// Sidebar material with the theme's wash on top, in that order.
    func sidebarSurface() -> some View {
        modifier(SidebarSurfaceModifier())
    }
}

private struct SidebarSurfaceModifier: ViewModifier {
    @Environment(\.themePalette) private var palette
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content.background {
            ZStack {
                if reduceTransparency {
                    Color(nsColor: .windowBackgroundColor)
                } else {
                    SidebarMaterial()
                }
                if let tint = palette.sidebarTint, !reduceTransparency {
                    tint
                }
            }
            .ignoresSafeArea()
        }
    }
}
