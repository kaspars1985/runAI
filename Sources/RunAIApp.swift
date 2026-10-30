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
    @Environment(\.colorScheme) private var colorScheme

    private var colors: ThemeColors {
        ThemeColors(theme: state.appTheme, colorScheme: colorScheme)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Galvene ar lietotnes ikonu, nosaukumu un statusu
            HStack(spacing: 9) {
                if let appIcon = AppIconImageHelper.loadIcon() {
                    Image(nsImage: appIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 26, height: 26)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    Image(systemName: "waveform")
                        .font(.system(size: 18))
                        .foregroundColor(colors.textPrimary)
                }

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text("runAI")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(colors.textPrimary)
                        Text(state.updateChecker.currentVersion)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(colors.textSecondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(colors.keycapBg)
                            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    }
                    HStack(spacing: 5) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 6, height: 6)
                        Text(state.status.hudText)
                            .font(.system(size: 10.5))
                            .foregroundColor(colors.textSecondary)
                    }
                }

                Spacer(minLength: 4)

                if state.updateChecker.updateAvailable {
                    Button {
                        state.updateChecker.openReleasePage()
                    } label: {
                        Text("v\(state.updateChecker.latestVersion ?? "")")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundColor(colors.badgeBlueText)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(colors.badgeBlueBg)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 2)

            // Galvenā ieraksta poga
            Button {
                state.toggleRecording()
            } label: {
                HStack(spacing: 8) {
                    if state.status == .recording {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                        Text("Apturēt un atšifrēt")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(colors.statusRed)
                        Spacer()
                        Text("Ieraksta…")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(colors.textSecondary)
                    } else if state.status == .transcribing {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                        Text("Atšifrē…")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(colors.textPrimary)
                        Spacer()
                    } else {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                        Text("Sākt ierakstu")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(colors.textPrimary)
                        Spacer()
                        Text(state.hotkey.label)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(colors.textMuted)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(state.status == .recording ? colors.statusRed.opacity(0.12) : colors.cardBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(state.status == .recording ? colors.statusRed.opacity(0.3) : colors.cardBorder, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(state.status == .transcribing || state.status == .loading)

            // Kartīte: Pašreizējais modelis un taustiņš
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Modelis")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(colors.textMuted)
                    Spacer()
                    Text(state.selectedModelTitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(colors.textPrimary)
                        .lineLimit(1)
                }

                Divider().opacity(0.4)

                HStack(alignment: .center) {
                    Text("Taustiņš")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(colors.textMuted)
                    Spacer()
                    Text(state.hotkey.label)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(colors.textPrimary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(colors.keycapBg)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(colors.cardBorder, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
            }
            .padding(9)
            .background(colors.cardBg)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(colors.cardBorder, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            // Darbību rindas
            VStack(spacing: 2) {
                MenuBarRowButton(title: "Iestatījumi…", icon: "gearshape", colors: colors) {
                    SettingsWindowController.shared.show()
                }
                MenuBarRowButton(title: "Atvērt modeļu mapi", icon: "folder", colors: colors) {
                    state.revealModelsFolder()
                }
                Divider().opacity(0.4).padding(.vertical, 2)
                MenuBarRowButton(title: "Iziet", icon: "power", colors: colors) {
                    NSApp.terminate(nil)
                }
            }
        }
        .padding(12)
        .frame(width: 250)
        .background(colors.canvasBg)
        .preferredColorScheme(state.appTheme.colorScheme)
    }

    private var statusColor: Color {
        switch state.status {
        case .recording: return .red
        case .transcribing: return .orange
        case .ready: return colors.statusGreen
        case .copied: return .blue
        case .needsModel: return .yellow
        case .loading: return .purple
        case .error: return colors.statusRed
        }
    }
}

// MARK: - Izvēlnes rindas poga

private struct MenuBarRowButton: View {
    let title: String
    let icon: String
    let colors: ThemeColors
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(colors.textSecondary)
                    .frame(width: 14)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(colors.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isHovered ? colors.keycapBg : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
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
        .menuBarExtraStyle(.window)
    }
}
