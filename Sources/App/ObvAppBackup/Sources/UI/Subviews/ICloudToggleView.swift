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


protocol ICloudToggleViewActions: AnyObject {
    @MainActor func usersWantsToGetBackupParameterIsSynchronizedWithICloud() async throws -> Bool
    @MainActor func usersWantsToChangeBackupParameterIsSynchronizedWithICloud(newIsSynchronizedWithICloud: Bool) async throws
}


/// Implements a toggle view that enables users to decide whether their device backup seed should be stored in the iCloud keychain or not.
/// The method supports two modes: `settingInitialValue` and `updatingValue`.
///
/// ## In the `settingInitialValue` mode
///
/// The `settingInitialValue` mode, used at most once during an app's lifetime when migrating from old backups to new ones, allows users to set the initial value for this parameter.
/// This mode is typically utilized in the `ChooseBetweenManualAndICloodBackupModeView`, which defines a @State variable used as binding for the `settingInitialValue` case.
///
/// ## In the `updatingValue` mode
///
/// The `updatingValue` mode expects to be employed when the parameter's value has already been set in the past. In this state, the view starts in a 'disabled' state and instantly
/// requests its delegate about the current value of the parameter, using the response (in practice, from the engine) to update the UI before enabling it.
/// Once enabled, users can modify the parameter value.
/// Each time the toggle is adjusted by the user, it is disabled temporarily while querying the delegate to change the setting, then updates with the new current value and re-enables the UI.
///
struct ICloudToggleView: View {
    
    let mode: Mode
    
    @State private var isBackupedOnICloudInUpdateMode: Bool = true // Only used in `.updatingValue` mode
    @State private var toggleDisabled: Bool = true

    @State private var presentFailureAlert: Bool = false
    @State private var errorOnChangeOfIsSynchronizedWithICloud: Error?
    
    enum Mode {
        case settingInitialValue(isBackupedOnICloud: Binding<Bool>)
        case updatingValue(actions: ICloudToggleViewActions)
    }
    
    private var isBackupedOnICloud: Binding<Bool> {
        switch mode {
        case .settingInitialValue(isBackupedOnICloud: let isBackupedOnICloud):
            return isBackupedOnICloud
        case .updatingValue:
            return $isBackupedOnICloudInUpdateMode
        }
    }
    
    
    private func onChangeOfIsBackupedOnICloudInUpdateMode(newValue: Bool) {        
        switch mode {
        case .settingInitialValue:
            assertionFailure()
            return
        case .updatingValue(actions: let actions):
            toggleDisabled = true
            Task {
                defer { toggleDisabled = false }
                do {
                    let currentValue = try await actions.usersWantsToGetBackupParameterIsSynchronizedWithICloud()
                    guard currentValue != newValue else { return }
                    try await actions.usersWantsToChangeBackupParameterIsSynchronizedWithICloud(newIsSynchronizedWithICloud: newValue)
                    self.isBackupedOnICloudInUpdateMode = try await actions.usersWantsToGetBackupParameterIsSynchronizedWithICloud()
                } catch {
                    self.isBackupedOnICloudInUpdateMode = !newValue
                    errorOnChangeOfIsSynchronizedWithICloud = error
                    presentFailureAlert = true
                }
            }
        }
    }
    
    
    private func onAppear() {
        switch mode {
        case .settingInitialValue:
            toggleDisabled = false
        case .updatingValue(actions: let actions):
            self.toggleDisabled = true
            Task {
                do {
                    self.isBackupedOnICloudInUpdateMode = try await actions.usersWantsToGetBackupParameterIsSynchronizedWithICloud()
                    self.toggleDisabled = false
                } catch {
                    assertionFailure()
                }
            }
        }
    }
    
    
    var body: some View {
        Toggle(isOn: isBackupedOnICloud) {
            HStack(alignment: .center) {
                Text("BACKUP_MY_PROFILE_ON_ICLOUD")
                Spacer()
                ProgressView()
                    .opacity(toggleDisabled ? 1 : 0)
            }
        }
        .disabled(toggleDisabled)
        .onAppear(perform: onAppear)
        .alert(String(localizedInThisBundle: "WE_COULD_NOT_CHANGE_ICLOUD_KEYCHAIN_SETTING"), isPresented: $presentFailureAlert) {
            Button(String(localizedInThisBundle: "OK"), action: {
                // Just dismiss the alert
            })
        } message: {
            if let errorDescription = errorOnChangeOfIsSynchronizedWithICloud?.localizedDescription {
                Text(errorDescription)
            }
        }
        .onChange(of: isBackupedOnICloudInUpdateMode) { newValue in
            onChangeOfIsBackupedOnICloudInUpdateMode(newValue: newValue)
        }
    }
}


// MARK: - Previews

private final class ActionsForPreviews: ICloudToggleViewActions {
    
    private var isSynchronizedWithICloud = true
    
    func usersWantsToGetBackupParameterIsSynchronizedWithICloud() async throws -> Bool {
        try! await Task.sleep(seconds: 1)
        return isSynchronizedWithICloud
    }
    
    func usersWantsToChangeBackupParameterIsSynchronizedWithICloud(newIsSynchronizedWithICloud: Bool) async throws {
        try! await Task.sleep(seconds: 1)
        //throw ObvErrorForPreviews.someError
        isSynchronizedWithICloud = newIsSynchronizedWithICloud
    }
        
    enum ObvErrorForPreviews: Error {
        case someError
    }
    
}


/// This view allows to preview the `ICloudToggleView` when initialized in `settingInitialValue` mode.
private struct DebugViewForSettingInitialValue: View {
    @State private var isBackupedOnICloud: Bool = false
    var body: some View {
        VStack {
            ICloudToggleView(mode: .settingInitialValue(isBackupedOnICloud: $isBackupedOnICloud))
        }
    }
}


#Preview("Setting initial value") {
    DebugViewForSettingInitialValue()
}

#Preview("Updating value") {
    ICloudToggleView(mode: .updatingValue(actions: ActionsForPreviews()))
}
