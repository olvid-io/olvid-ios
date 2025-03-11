/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
import ObvTypes
import Combine
import ObvCrypto


protocol TransfertProtocolTargetCodeFormViewActionsProtocol: AnyObject {
    func userEnteredTransferSessionNumberOnTargetDevice(transferSessionNumber: ObvOwnedIdentityTransferSessionNumber, onIncorrectTransferSessionNumber: @escaping () -> Void, onAvailableSas: @escaping (UID, ObvOwnedIdentityTransferSas) -> Void) async throws
    func sasIsAvailable(protocolInstanceUID: UID, sas: ObvOwnedIdentityTransferSas) async
}


struct TransfertProtocolTargetCodeFormView: View, SessionNumberTextFieldActionsProtocol {
    
    let actions: TransfertProtocolTargetCodeFormViewActionsProtocol
    
    private enum AlertType {
        case userEnteredIncorrectSessionNumber
        case seriousError
    }
    
    @State private var enteredTransferSessionNumber: ObvOwnedIdentityTransferSessionNumber?
    @State private var engineIsProcessingEnteredSessionNumber = false
    @State private var sasAvailable = false
    @State private var shownAlert: AlertType? = nil
    
    // SessionNumberTextFieldActionsProtocol
    
    func userEnteredSessionNumber(sessionNumber: String) async {
        guard let sessionNumber = try? Int(sessionNumber, format: .number) else { assertionFailure(); return }
        guard let transferSessionNumber = try? ObvOwnedIdentityTransferSessionNumber(sessionNumber: sessionNumber) else { return }
        shownAlert = nil
        withAnimation {
            enteredTransferSessionNumber = transferSessionNumber
        }
    }
    
    
    func userIsTypingSessionNumber() {
        shownAlert = nil
        withAnimation {
            enteredTransferSessionNumber = nil
        }
    }

    
    private func userTappedConfirmButton() {
        guard let enteredTransferSessionNumber else { assertionFailure(); return }
        withAnimation {
            engineIsProcessingEnteredSessionNumber = true
            shownAlert = nil
        }
        Task {
            do {
                try await actions.userEnteredTransferSessionNumberOnTargetDevice(
                    transferSessionNumber: enteredTransferSessionNumber,
                    onIncorrectTransferSessionNumber: { Task { await onIncorrectTransferSessionNumber() } }, 
                    onAvailableSas: { (uid, sas) in Task { await onAvailableSas(uid, sas) } })
            } catch {
                engineIsProcessingEnteredSessionNumber = false
                shownAlert = .seriousError
            }
        }
    }
    
    
    /// Called by the engine if the `enteredTransferSessionNumber` happens to be incorrect
    @MainActor
    private func onIncorrectTransferSessionNumber() async {
        withAnimation {
            engineIsProcessingEnteredSessionNumber = false
            shownAlert = .userEnteredIncorrectSessionNumber
        }
    }

    
    /// Called by the engine if something went really wrong
    @MainActor
    private func onAvailableSas(_ protocolInstanceUID: UID, _ sas: ObvOwnedIdentityTransferSas) async {
        shownAlert = nil
        engineIsProcessingEnteredSessionNumber = false
        sasAvailable = true
        await actions.sasIsAvailable(protocolInstanceUID: protocolInstanceUID, sas: sas)
    }

    
    private func alertTitle(for alertType: AlertType) -> LocalizedStringKey {
        switch alertType {
        case .userEnteredIncorrectSessionNumber:
            return "OWNED_IDENTITY_TRANSFER_INCORRECT_TRANSFER_SESSION_NUMBER"
        case .seriousError:
            return "OWNED_IDENTITY_TRANSFER_INCORRECT_SERIOUS_ERROR"
        }
    }
    
    
    var body: some View {
        VStack {
            
            ScrollView {
                
                ScrollViewReader { reader in
                    
                    NewOnboardingHeaderView(title: "OWNED_IDENTITY_TRANSFER_ENTER_CODE_FROM_OTHER_DEVICE", subtitle: nil)
                    
                    Text("OWNED_IDENTITY_TRANSFER_ENTER_CODE_FROM_OTHER_DEVICE_BODY")
                        .font(.body)
                        .padding(.top)
                    
                    SessionNumberTextField(actions: self, model: .init(mode: .enterSessionNumber))
                        .id("SessionNumberTextField")
                        .padding(.top)
                        .disabled(engineIsProcessingEnteredSessionNumber || sasAvailable)
                        .onTapGesture {
                            // Allows the text field to be properly above the keyboard, the automatic scrolling is not enough
                            if UIDevice.current.userInterfaceIdiom == .phone {
                                reader.scrollTo("SessionNumberTextField", anchor: .top)
                            }
                        }
                    
                    ProgressView()
                        .opacity(engineIsProcessingEnteredSessionNumber ? 1.0 : 0)
                    
                    if let shownAlert {
                        HStack {
                            Label(
                                title: { Text(alertTitle(for: shownAlert)) },
                                icon: {
                                    Image(systemIcon: .xmarkCircle)
                                        .renderingMode(.template)
                                        .foregroundColor(Color(.systemRed))
                                })
                            Spacer()
                        }
                    }
                    
                }
                
            }
            
            InternalButton("OWNED_IDENTITY_TRANSFER_ENTER_CODE_FROM_OTHER_DEVICE_BUTTON_TITLE", action: userTappedConfirmButton)
                .disabled(enteredTransferSessionNumber == nil || engineIsProcessingEnteredSessionNumber || sasAvailable)
                .padding(.bottom)
            
        }
        .padding(.horizontal)
    }
    
    
}


protocol SessionNumberTextFieldActionsProtocol {
    func userEnteredSessionNumber(sessionNumber: String) async
    func userIsTypingSessionNumber()
}


struct SessionNumberTextField: View, SingleDigitTextFielddActions {
    
    let actions: SessionNumberTextFieldActionsProtocol
    let model: Model
    
    enum Mode {
        case showSessionNumber(sessionNumber: ObvOwnedIdentityTransferSessionNumber)
        case enterSessionNumber
    }

    struct Model {
        let mode: Mode
    }

    @State private var textValue0: String = ""
    @State private var textValue1: String = ""
    @State private var textValue2: String = ""
    @State private var textValue3: String = ""
    @State private var textValue4: String = ""
    @State private var textValue5: String = ""
    @State private var textValue6: String = ""
    @State private var textValue7: String = ""

    private var textValues: [String] {
        [textValue0, textValue1, textValue2, textValue3,
         textValue4, textValue5, textValue6, textValue7]
    }

    @FocusState private var indexOfFocusedField: Int?

    private func clearAll() {
        textValue0 = ""
        textValue1 = ""
        textValue2 = ""
        textValue3 = ""
        textValue4 = ""
        textValue5 = ""
        textValue6 = ""
        textValue7 = ""
        indexOfFocusedField = nil
    }

    
    private var showClearButton: Bool {
        switch model.mode {
        case .enterSessionNumber:
            return true
        case .showSessionNumber:
            return false
        }
    }
    
    
    // SingleTextFieldActions
    
    /// Called by the ``SingleTextField`` at index `index` each time its text value changes.
    func singleTextFieldDidChangeAtIndex(_ index: Int) {
        gotoNextTextFieldIfPossible(fromIndex: index)
        if let enteredSessionNumber {
            indexOfFocusedField = nil
            Task {
                await actions.userEnteredSessionNumber(sessionNumber: enteredSessionNumber)
            }
        } else {
            actions.userIsTypingSessionNumber()
        }
    }

    // Helpers
    
    /// Returns an 8 characters session number if the texts in the text fields allow to compute one.
    /// Returns `nil` otherwise.
    private var enteredSessionNumber: String? {
        let concatenation = textValues
            .reduce("", { $0 + $1 })
            .removingAllCharactersNotInCharacterSet(.decimalDigits)
        return concatenation.count == ObvOwnedIdentityTransferSessionNumber.expectedCount ? concatenation : nil
    }

    private func gotoNextTextFieldIfPossible(fromIndex: Int) {
        guard fromIndex < 7 else { return }
        let toIndex = fromIndex + 1
        if textValues[fromIndex].count == 1, textValues[toIndex].count < 1 {
            indexOfFocusedField = toIndex
        }
    }


    // Body
    
    var body: some View {
        VStack {
            HStack {
                SingleDigitTextField("X", text: $textValue0, actions: self, model: .init(index: 0))
                SingleDigitTextField("X", text: $textValue1, actions: self, model: .init(index: 1))
                    .focused($indexOfFocusedField, equals: 1)
                SingleDigitTextField("X", text: $textValue2, actions: self, model: .init(index: 2))
                    .focused($indexOfFocusedField, equals: 2)
                SingleDigitTextField("X", text: $textValue3, actions: self, model: .init(index: 3))
                    .focused($indexOfFocusedField, equals: 3)
                SingleDigitTextField("X", text: $textValue4, actions: self, model: .init(index: 4))
                    .focused($indexOfFocusedField, equals: 4)
                SingleDigitTextField("X", text: $textValue5, actions: self, model: .init(index: 5))
                    .focused($indexOfFocusedField, equals: 5)
                SingleDigitTextField("X", text: $textValue6, actions: self, model: .init(index: 6))
                    .focused($indexOfFocusedField, equals: 6)
                SingleDigitTextField("X", text: $textValue7, actions: self, model: .init(index: 7))
                    .focused($indexOfFocusedField, equals: 7)
            }
            if showClearButton {
                HStack {
                    Spacer()
                    Button("CLEAR_ALL".localizedInThisBundle, action: clearAll)
                }.padding(.top, 4)
            }
        }
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
                .padding(.horizontal, 26)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
        }
        .background(Color.blue01)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .opacity(isEnabled ? 1.0 : 0.6)
    }
    
}


// MARK: - Private helpers

fileprivate extension String {
    func removingAllCharactersNotInCharacterSet(_ characterSet: CharacterSet) -> String {
        return String(self
            .trimmingWhitespacesAndNewlines()
            .unicodeScalars
            .filter({
                characterSet.contains($0)
            }))
    }
}


// MARK: - Previews


struct TransfertProtocolTargetCodeFormView_Previews: PreviewProvider {
    
    
    private final class ActionsForPreviews: TransfertProtocolTargetCodeFormViewActionsProtocol {

        private static let protocolInstanceUIDForPreviews = UID.zero
        private static let sasForPreviews = try! ObvOwnedIdentityTransferSas(fullSas: "12345678".data(using: .utf8)!)

        func userEnteredTransferSessionNumberOnTargetDevice(transferSessionNumber: ObvOwnedIdentityTransferSessionNumber, onIncorrectTransferSessionNumber: @escaping () -> Void, onAvailableSas: @escaping (UID, ObvOwnedIdentityTransferSas) -> Void) async throws {
            
            try! await Task.sleep(seconds: 1)
            
            if transferSessionNumber.sessionNumber == 0 {
                onAvailableSas(Self.protocolInstanceUIDForPreviews, Self.sasForPreviews)
            } else {
                onIncorrectTransferSessionNumber()
            }
            
        }
        
        func sasIsAvailable(protocolInstanceUID: UID, sas: ObvOwnedIdentityTransferSas) async {}
        
    }
    
    private static let actions = ActionsForPreviews()
    
    private enum ObvError: Error {
        case fakeErrorForPreviews
    }
    
    static var previews: some View {
        TransfertProtocolTargetCodeFormView(actions: actions)
    }
    
}
