import SwiftUI

extension View {
    func onDoubleClick(handler: @escaping () -> Void) -> some View {
        modifier(DoubleClickHandler(handler: handler))
    }
}

struct DoubleClickHandler: ViewModifier {
    let handler: () -> Void

    func body(content: Content) -> some View {
        content.overlay {
            DoubleClickListeningViewRepresentable(handler: handler)
        }
    }
}

struct DoubleClickListeningViewRepresentable: NSViewRepresentable {
    let handler: () -> Void

    func makeNSView(context: Context) -> DoubleClickListeningView {
        DoubleClickListeningView(handler: handler)
    }

    func updateNSView(_ nsView: DoubleClickListeningView, context: Context) {
        nsView.handler = handler
    }
}

class DoubleClickListeningView: NSView {
    var handler: () -> Void
    private var monitor: Any?

    init(handler: @escaping () -> Void) {
        self.handler = handler
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil && monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                guard let self else { return event }
                if event.clickCount == 2 {
                    let locationInView = self.convert(event.locationInWindow, from: nil)
                    if self.bounds.contains(locationInView) {
                        self.handler()
                    }
                }
                return event
            }
        } else if window == nil {
            removeMonitor()
        }
    }

    override func removeFromSuperview() {
        removeMonitor()
        super.removeFromSuperview()
    }

    // Transparent to hit testing — lets the Button underneath receive all clicks
    override func hitTest(_ aPoint: NSPoint) -> NSView? {
        return nil
    }

    private func removeMonitor() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
