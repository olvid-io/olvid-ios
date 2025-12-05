/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
 *
 *  This file is part of Olvid for iOS.
 *
 *  Olvid is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU Affero General Public License, version 3,
 *  as published by the Free Software Foundation.
 *
 *  Olvid is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU Affero General Public License for more details.
 *
 *  You should have received a copy of the GNU Affero General Public License
 *  along with Olvid.  If not, see <https://www.gnu.org/licenses/>.
 */

import SwiftUI
import ObvSettings

struct BetaSettingsActivationView: View {
    
    init(isAccessToAdvancedSettingsEnabled: Bool) {
        self.isAccessToAdvancedSettingsEnabled = isAccessToAdvancedSettingsEnabled
    }
    
    @State private var isAccessToAdvancedSettingsEnabled: Bool
    
    @Environment(\.dismiss) var dismiss
    
    private func userWantsToSaveSettings() {
        ObvMessengerSettings.BetaConfiguration.showBetaSettings = isAccessToAdvancedSettingsEnabled
        dismiss()
    }
    
    private func userWantsToCancel() {
        dismiss()
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    Toggle("ACCESS_TO_ADVANCED_SETTINGS", isOn: $isAccessToAdvancedSettingsEnabled)
                }
            }
            .navigationTitle(Text("SETTINGS_UPDATE_TITLE"))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: userWantsToSaveSettings,
                           label: {
                        if #available(iOS 26, *) {
                            Image(systemIcon: .checkmark)
                        } else {
                            Image(systemIcon: .checkmarkCircleFill)
                        }
                    })
                    .buttonStyle(.borderedProminent)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: userWantsToCancel,
                           label: {
                        if #available(iOS 26, *) {
                            Image(systemIcon: .xmark)
                        } else {
                            Image(systemIcon: .xmarkSealFill)
                        }
                    })
                }
            }
        }
    }
}

#Preview {
    BetaSettingsActivationView(isAccessToAdvancedSettingsEnabled: true)
}
