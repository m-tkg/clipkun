import SwiftUI
import AppKit
import KunAppKit
import ClipkunCore

/// 設定ダイアログの編集状態。変更は即時反映する（Apply/OK は持たない）。
@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var settings: ClipkunCore.Settings {
        didSet {
            guard settings != oldValue else { return }
            onChange(settings)
        }
    }
    private let onChange: (ClipkunCore.Settings) -> Void

    init(settings: ClipkunCore.Settings, onChange: @escaping (ClipkunCore.Settings) -> Void) {
        self.settings = settings
        self.onChange = onChange
    }
}

/// 設定ダイアログ本体。タブで機能ごとの設定を切り替える。各変更は即座に反映・保存される。
struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var loginItem: LoginItemController

    @State private var loginItemError: String?

    var body: some View {
        TabView {
            GeneralSettingsTab(loginItem: loginItem, errorMessage: $loginItemError)
                .tabItem { Text(L.string("tab.general")) }

            HistorySettingsTab(settings: $viewModel.settings)
                .tabItem { Text(L.string("tab.history")) }
        }
        .padding()
        .frame(width: 460, height: 400)
        .alert(L.string("alert.error.title"), isPresented: Binding(
            get: { loginItemError != nil },
            set: { if !$0 { loginItemError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(loginItemError ?? "")
        }
    }
}

/// 「一般」タブ。ログイン時の自動起動とバージョン表示。
struct GeneralSettingsTab: View {
    @ObservedObject var loginItem: LoginItemController
    @SwiftUI.Binding var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Toggle(L.string("settings.launch_at_login"), isOn: Binding(
                get: { loginItem.isEnabled },
                set: { newValue in
                    if let message = loginItem.setEnabled(newValue) {
                        errorMessage = message
                    }
                }
            ))

            Text(L.format("settings.version", UpdateService.currentVersion))
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// 「ホットキー・保持期間」タブ。ポップアップのホットキー、保持期間、最大件数。
struct HistorySettingsTab: View {
    @SwiftUI.Binding var settings: ClipkunCore.Settings

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text(L.string("settings.hotkey"))
                Spacer(minLength: 12)
                HotKeyRecorderView(config: $settings.popupHotKey)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(L.string("settings.retention"))
                Spacer(minLength: 12)
                Picker("", selection: amountBinding) {
                    ForEach(Array(RetentionPeriod.validRange(for: settings.retention.unit)), id: \.self) { value in
                        Text("\(value)").tag(value)
                    }
                }
                .labelsHidden()
                .frame(width: 70)
                Picker("", selection: unitBinding) {
                    Text(L.string("unit.hours")).tag(RetentionPeriod.Unit.hours)
                    Text(L.string("unit.days")).tag(RetentionPeriod.Unit.days)
                }
                .labelsHidden()
                .frame(width: 90)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(L.string("settings.max_items"))
                Spacer(minLength: 12)
                Stepper(value: maxItemsBinding, in: Settings.maxItemCountRange, step: 10) {
                    Text("\(settings.maxItemCount)")
                        .monospacedDigit()
                        .frame(width: 48, alignment: .trailing)
                }
            }

            HStack(alignment: .firstTextBaseline) {
                Text(L.string("settings.popup_position"))
                Spacer(minLength: 12)
                Picker("", selection: $settings.popupPosition) {
                    Text(L.string("popup_position.cursor")).tag(PopupPosition.cursor)
                    Text(L.string("popup_position.center")).tag(PopupPosition.screenCenter)
                }
                .labelsHidden()
                .frame(width: 160)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(L.string("settings.background_opacity"))
                Slider(value: $settings.popupBackgroundOpacity, in: Settings.backgroundOpacityRange)
                Text(String(format: "%.0f%%", settings.popupBackgroundOpacity * 100))
                    .font(.caption).monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }

            Text(L.string("settings.history.description"))
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // RetentionPeriod は不変値型のため、変更時は新しい値を作って差し替える。
    private var unitBinding: SwiftUI.Binding<RetentionPeriod.Unit> {
        SwiftUI.Binding(
            get: { settings.retention.unit },
            set: { settings.retention = RetentionPeriod(unit: $0, amount: settings.retention.amount) }
        )
    }

    private var amountBinding: SwiftUI.Binding<Int> {
        SwiftUI.Binding(
            get: { settings.retention.amount },
            set: { settings.retention = RetentionPeriod(unit: settings.retention.unit, amount: $0) }
        )
    }

    private var maxItemsBinding: SwiftUI.Binding<Int> {
        SwiftUI.Binding(
            get: { settings.maxItemCount },
            set: { settings.maxItemCount = $0 }
        )
    }
}
