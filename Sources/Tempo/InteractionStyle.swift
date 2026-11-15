import SwiftUI

struct TempoButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { HoverButton(configuration: configuration) }
    private struct HoverButton: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var enabled
        @State private var hovered = false
        var body: some View {
            configuration.label
                .background(Color.accent.opacity(enabled && (hovered || configuration.isPressed) ? (configuration.isPressed ? 0.18 : 0.10) : 0), in: RoundedRectangle(cornerRadius: 5))
                .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(Color.accent.opacity(enabled && hovered ? 0.3 : 0)) }
                .opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
                .contentShape(Rectangle()).onHover { hovered = $0 }
                .animation(.easeOut(duration: 0.1), value: hovered)
        }
    }
}
extension ButtonStyle where Self == TempoButtonStyle { static var tempo: TempoButtonStyle { .init() } }
struct HoverFeedback: ViewModifier {
    @State private var hovered = false
    func body(content: Content) -> some View {
        content.overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(Color.accent.opacity(hovered ? 0.3 : 0)) }
            .background(Color.accent.opacity(hovered ? 0.035 : 0), in: RoundedRectangle(cornerRadius: 7))
            .onHover { hovered = $0 }
    }
}
extension View { func hoverFeedback() -> some View { modifier(HoverFeedback()) } }
