/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
import ObvDesignSystem


protocol CurrentDeviceNameChooserViewActionsProtocol: AnyObject {
    func userDidChooseCurrentDeviceName(deviceName: String) async
}


struct CurrentDeviceNameChooserView: View {
    
    let actions: CurrentDeviceNameChooserViewActionsProtocol
    let model: Model
    
    struct Model {
        let defaultDeviceName: String
    }
    
    @State private var deviceName = "";
    @State private var deviceNameSetWithDefaultName = false
    @State private var isButtonDisabled = true
    @State private var isInterfaceDisabled = false

    
    private func isResetButtonDisabled() {
        isButtonDisabled = deviceName.trimmingWhitespacesAndNewlines().isEmpty
    }

    private func userDidChooseCurrentDeviceName() {
        isInterfaceDisabled = true
        Task { await actions.userDidChooseCurrentDeviceName(deviceName: deviceName) }
    }
    
    var body: some View {
        ScrollView {
            VStack {
                
                ObvHeaderView(title: "ONBOARDING_DEVICE_NAME_CHOOSER_TITLE".localizedInThisBundle,
                              subtitle: "ONBOARDING_DEVICE_NAME_CHOOSER_SUBTITLE".localizedInThisBundle)
                    .padding(.bottom, 40)

                InternalTextField("ONBOARDING_DEVICE_NAME_CHOOSER_TEXTFIELD_\(model.defaultDeviceName)", text: $deviceName)
                    .onChange(of: deviceName) { _ in isResetButtonDisabled() }
                    .padding(.bottom)
                
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }.opacity(isInterfaceDisabled ? 1.0 : 0.0)

                InternalButton("ONBOARDING_DEVICE_NAME_CHOOSER_BUTTON_TITLE", action: userDidChooseCurrentDeviceName)
                .disabled(isButtonDisabled)
                .padding(.top, 20)
                                
            }
            .padding(.horizontal)
        }
        .onAppear {
            isInterfaceDisabled = false
            guard !deviceNameSetWithDefaultName else { return }
            deviceNameSetWithDefaultName = true
            deviceName = String(localizedInThisBundle: "MY_DEVICE_NAME_\(model.defaultDeviceName)")
        }
        .disabled(isInterfaceDisabled)
    }
    
}


// MARK: - Button used in this view only

private struct InternalButton: View {
    
    private let key: LocalizedStringKey
    private let action: () -> Void
    @Environment(\.isEnabled) var isEnabled
    
    init(_ key: LocalizedStringKey, action: @escaping () -> Void) {
        self.key = key
        self.action = action
    }
        
    var body: some View {
        Button(action: action) {
            Text(key)
                .foregroundStyle(.white)
                .padding(.horizontal, 30)
                .padding(.vertical, 24)
        }
        .background(Color.blue01)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .opacity(isEnabled ? 1.0 : 0.6)
    }
    
}


// MARK: - Text field used in this view only

private struct InternalTextField: View {
    
    private let key: String.LocalizationValue
    private let text: Binding<String>
    
    init(_ key: String.LocalizationValue, text: Binding<String>) {
        self.key = key
        self.text = text
    }
    
    var body: some View {
        TextField(String(localizedInThisBundle: key), text: text)
            .padding()
            .background(Color.textFieldBackgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
}


struct CurrentDeviceNameChooserViewActionsProtocol_Previews: PreviewProvider {
    
    final class ActionsForPreviews: CurrentDeviceNameChooserViewActionsProtocol{
        func userDidChooseCurrentDeviceName(deviceName: String) {}
    }
    
    private static let actions = ActionsForPreviews()
    
    private static let model = CurrentDeviceNameChooserView.Model(
        defaultDeviceName: "iPhone 15")
    
    static var previews: some View {
        CurrentDeviceNameChooserView(actions: actions, model: model)
    }
    
}
