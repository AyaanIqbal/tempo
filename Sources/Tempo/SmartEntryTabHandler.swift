import SwiftUI
import AppKit

/// Intercept Tab before AppKit uses it to move focus out of the task field.
struct SmartEntryTabHandler: NSViewRepresentable {
    let enabled: Bool
    let handle: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.view = view
        context.coordinator.start()
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.enabled = enabled
        context.coordinator.handle = handle
    }
    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        if let monitor = coordinator.monitor { NSEvent.removeMonitor(monitor) }
        coordinator.monitor = nil
    }
    @MainActor final class Coordinator {
        weak var view: NSView?
        var enabled = false
        var handle: ((Bool) -> Void)?
        var monitor: Any?
        func start() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let handled = MainActor.assumeIsolated {
                    guard let self, self.enabled, event.keyCode == 48,
                          let window = self.view?.window, event.window === window,
                          event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
                    self.handle?(event.modifierFlags.contains(.shift))
                    return true
                }
                return handled ? nil : event
            }
        }
    }
}
