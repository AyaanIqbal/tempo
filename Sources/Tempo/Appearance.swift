import SwiftUI
import AppKit

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { switch self { case .system: "System"; case .light: "Light"; case .dark: "Dark" } }
    var colorScheme: ColorScheme? { switch self { case .system: nil; case .light: .light; case .dark: .dark } }
    var nativeAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

struct AppearanceSettings: View {
    @AppStorage("tempo.appearance") private var appearance: AppAppearance = .system
    var body: some View {
        Form {
            Picker("Appearance", selection: $appearance) {
                ForEach(AppAppearance.allCases) { value in Text(value.title).tag(value) }
            }.pickerStyle(.segmented)
            Text("System follows your Mac's appearance. Your choice is saved on this Mac.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }.padding(26).frame(width: 390).preferredColorScheme(appearance.colorScheme)
            .onChange(of: appearance) { NSApp.appearance = appearance.nativeAppearance }
    }
}
