import SwiftUI
import AppKit

// MARK: - Iestatījumu logs

final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?
    private var hosting: NSHostingController<SettingsView>?

    func show() {
        let isFirstTime = (window == nil)
        if isFirstTime {
            let view = SettingsView(state: AppState.shared)
            let hosting = NSHostingController(rootView: view)
            self.hosting = hosting

            let w = NSWindow(contentViewController: hosting)
            w.title = "runAI iestatījumi"
            w.styleMask = [.titled, .closable, .miniaturizable]
            w.isReleasedWhenClosed = false
            window = w
        }

        applyAppearance()

        // Dinamiski pielāgo loga augstumu saturam (bez ritināšanas)
        if let hosting = hosting, let w = window {
            let fitting = hosting.sizeThatFits(in: NSSize(width: 760, height: CGFloat.greatestFiniteMagnitude))
            w.setContentSize(NSSize(width: 760, height: max(fitting.height, 570)))
            if isFirstTime {
                w.center()
            }
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func updateAppearance(_ appearance: NSAppearance?) {
        applyAppearance()
    }

    private func applyAppearance() {
        guard let w = window else { return }
        let theme = AppState.shared.appTheme
        let appearance = theme.nsAppearance

        w.appearance = appearance
        hosting?.view.appearance = appearance

        switch theme {
        case .system:
            w.backgroundColor = nil
        case .light:
            w.backgroundColor = NSColor(red: 0.984, green: 0.984, blue: 0.980, alpha: 1.0)
        case .dark:
            w.backgroundColor = NSColor(red: 0.078, green: 0.078, blue: 0.086, alpha: 1.0)
        }

        if let hosting = hosting {
            let fitting = hosting.sizeThatFits(in: NSSize(width: 760, height: CGFloat.greatestFiniteMagnitude))
            w.setContentSize(NSSize(width: 760, height: max(fitting.height, 570)))
        }

        w.contentView?.needsDisplay = true
        w.invalidateShadow()
    }
}

// MARK: - Izvēlnes joslas ikona

struct MenuBarIcon: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        if state.status == .recording {
            Image(systemName: "record.circle.fill")
                .foregroundColor(.red)
        } else if state.status == .transcribing {
            Image(systemName: "sparkles")
                .foregroundColor(.orange)
        } else {
            Image(systemName: state.menuBarIconStyle.rawValue.isEmpty ? "waveform" : state.menuBarIconStyle.rawValue)
                .renderingMode(.template)
        }
    }
}

// MARK: - Izvēlnes saturs

struct MenuBarView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Galvene ar lietotnes ikonu un statusu
            HStack(spacing: 10) {
                if let appIcon = AppIconImageHelper.loadIcon() {
                    Image(nsImage: appIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 30, height: 30)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                } else {
                    Image(systemName: "waveform")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                }
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text("runAI")
                            .font(.headline)
                            .fontWeight(.bold)
                        Circle()
                            .fill(statusColor)
                            .frame(width: 7, height: 7)
                    }
                    Text(state.status.hudText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.vertical, 2)

            if state.updateChecker.updateAvailable {
                Divider()
                Button(action: { state.updateChecker.openReleasePage() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundColor(.accentColor)
                        Text("Pieejams atjauninājums (v\(state.updateChecker.latestVersion ?? ""))")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                }
                .buttonStyle(.plain)
            }

            Divider()

            // Dati par modeli un taustiņu
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("Modelis:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(state.selectedModelTitle)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                HStack {
                    Text("Taustiņš:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(state.hotkey.label)
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }

            Divider()

            Button("Iestatījumi…") { SettingsWindowController.shared.show() }
            Button("Atvērt mapi ar modeļiem") { state.revealModelsFolder() }

            Divider()

            Button("Iziet") { NSApp.terminate(nil) }
        }
        .padding(10)
        .frame(minWidth: 230, alignment: .leading)
    }

    private var statusColor: Color {
        switch state.status {
        case .recording: return .red
        case .transcribing: return .orange
        case .ready: return .green
        case .copied: return .blue
        case .needsModel: return .yellow
        case .loading: return .purple
        case .error: return .red
        }
    }
}

// MARK: - AppDelegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppState.shared.setup()

        // Ja modelis vēl nav lejupielādēts, uzreiz parādām iestatījumu logu
        if AppState.shared.status == .needsModel {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                SettingsWindowController.shared.show()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindowController.shared.show()
        return true
    }
}

// MARK: - Ieejas punkts

@main
struct RunAIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView().environmentObject(state)
        } label: {
            MenuBarIcon().environmentObject(state)
        }
    }
}
