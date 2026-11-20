import AppKit
import SwiftUI

/// Kurze Einblendung mitten auf dem Bildschirm (wie die Lautstärke-Anzeige von macOS) –
/// sofort beim Tastenkürzel, auch wenn das Fenster des Dock Organizers geschlossen ist.
@MainActor
final class HUD {
    static let shared = HUD()

    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?

    func show(_ title: String, subtitle: String? = nil, symbol: String = "dock.rectangle") {
        let panel = self.panel ?? makePanel()
        self.panel = panel

        let host = NSHostingView(rootView: HUDView(title: title, subtitle: subtitle, symbol: symbol))
        let size = host.fittingSize
        panel.contentView = host
        // Auf dem Bildschirm mit der Maus, etwas unterhalb der Mitte
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let f = screen?.visibleFrame {
            panel.setFrame(NSRect(x: f.midX - size.width / 2, y: f.minY + f.height * 0.3,
                                  width: size.width, height: size.height), display: true)
        }

        hideWork?.cancel()
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        let work = DispatchWorkItem { [weak self] in
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.35
                panel.animator().alphaValue = 0
            }, completionHandler: {
                MainActor.assumeIsolated {
                    if self?.hideWork?.isCancelled == false { panel.orderOut(nil) }
                }
            })
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: work)
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return p
    }
}

private struct HUDView: View {
    let title: String
    let subtitle: String?
    let symbol: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title2.bold())
                .lineLimit(1)
            if let subtitle {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 24)
        .frame(minWidth: 220)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(12)   // Platz, damit der Rand nicht abgeschnitten wird
    }
}
