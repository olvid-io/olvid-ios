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
import Combine


protocol EnterBackupKeyViewActionsProtocol: AnyObject {
    func recoverBackupFromEncryptedBackup(_ encryptedBackup: Data, backupKey: String) async throws -> (backupRequestIdentifier: UUID, backupDate: Date)
    func userWantsToRestoreBackup(backupRequestIdentifier: UUID) async throws
}


private enum EnteredBackupKeyStatus {
    
    /// When a backup key is entered, it is immediately used to try to decrypt the encryted backup
    /// If the decryption succeeds (at the engine level), we set this value which will later be used to
    /// inform the engine that we want to restore the backup on the basis of the decrypted backup identifier by
    /// this `backupRequestIdentifier`.
    case correct(backupRequestIdentifier: UUID)

    case incorrect
}


struct EnterBackupKeyView: View, BackupKeyTextFieldActionsProtocol {
    
    let model: Model
    let actions: EnterBackupKeyViewActionsProtocol
    
    @State private var enteredBackupKeyStatus: EnteredBackupKeyStatus?
    @State private var backupKeyCurrentlyChecked: String?
    @State private var isInterfaceDisabled = false

    struct Model {
        let encryptedBackup: Data
        let acceptableCharactersForBackupKeyString: CharacterSet
    }
    
    /// Called when the user entered a complete 32 characters backup key
    @MainActor
    func userEnteredBackupKey(backupKey: String) async {

        guard backupKeyCurrentlyChecked != backupKey else { return }
        backupKeyCurrentlyChecked = backupKey
        enteredBackupKeyStatus = nil

        let backupRequestIdentifier = try? await actions.recoverBackupFromEncryptedBackup(model.encryptedBackup, backupKey: backupKey).backupRequestIdentifier

        guard backupKeyCurrentlyChecked == backupKey else { return }
        if let backupRequestIdentifier {
            enteredBackupKeyStatus = .correct(backupRequestIdentifier: backupRequestIdentifier)
        } else {
            enteredBackupKeyStatus = .incorrect
        }
        backupKeyCurrentlyChecked = nil

    }
    
    
    func userIsTypingBackupKey() {
        enteredBackupKeyStatus = nil
    }
    

    private var showClearButton: Bool {
        switch enteredBackupKeyStatus {
        case .correct:
            return false
        default:
            return true
        }
    }

    
    private func userWantsToRestoreBackup(backupRequestIdentifier: UUID) {
        isInterfaceDisabled = true
        Task {
            try? await actions.userWantsToRestoreBackup(backupRequestIdentifier: backupRequestIdentifier)
        }
    }
    
    
    private func viewDidAppear() {
        isInterfaceDisabled = false
    }
    
    
    var body: some View {
        VStack {
            ScrollView {
                VStack {
                    
                    // Vertically center the view, but not on iPhone
                    
                    if UIDevice.current.userInterfaceIdiom != .phone {
                        Spacer()
                    }
                    
                    NewOnboardingHeaderView(
                        title: "ONBOARDING_ENTER_BACKUP_KEY",
                        subtitle: nil)
                    .padding(.bottom, 35)
                    
                    BackupKeyTextField(model: .init(showClearButton: showClearButton, acceptableCharactersForBackupKeyString: model.acceptableCharactersForBackupKeyString),
                                       actions: self)
                    .padding(.horizontal)
                    
                    Spacer()
                    
                    if let enteredBackupKeyStatus {
                        EnteredBackupKeyStatusReportView(enteredBackupKeyStatus: enteredBackupKeyStatus)
                            .padding(.horizontal)
                            .padding(.top)
                    }
                    
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding(.top)
                    .opacity(isInterfaceDisabled ? 1.0 : 0.0)
                    
                }
            }
            switch enteredBackupKeyStatus {
            case .correct(let backupRequestIdentifier):
                ValidateButton(action: { userWantsToRestoreBackup(backupRequestIdentifier: backupRequestIdentifier) })
                    .padding()
            default:
                EmptyView()
            }
        }
        .onAppear(perform: viewDidAppear)
        .disabled(isInterfaceDisabled)
    }
    
}


// MARK: - Internal validate button

private struct ValidateButton: View {

    let action: () -> Void
        
    @Environment(\.isEnabled) var isEnabled

    var body: some View {
        Button(action: action) {
            Label("Restore this backup", systemIcon: .checkmarkCircleFill)
                .lineLimit(1)
                .foregroundStyle(.white)
                .padding(.vertical)
                .frame(maxWidth: .infinity)
        }
        .background(Color("Blue01"))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .opacity(isEnabled ? 1.0 : 0.6)
    }
    
}



private struct EnteredBackupKeyStatusReportView: View {
    
    let enteredBackupKeyStatus: EnteredBackupKeyStatus
    
    private var imageSystemName: String {
        switch enteredBackupKeyStatus {
        case .correct:
            return "checkmark.circle.fill"
        case .incorrect:
            return "exclamationmark.circle.fill"
        }
    }

    
    private var imageColor: Color {
        switch enteredBackupKeyStatus {
        case .correct:
            return Color(UIColor.systemGreen)
        case .incorrect:
            return Color(UIColor.red)
        }
    }

    
    private var title: LocalizedStringKey {
        switch enteredBackupKeyStatus {
        case .correct:
            return "The backup key is correct"
        case .incorrect:
            return "The backup key is incorrect"
        }
    }

    
    private var description: LocalizedStringKey? {
        switch enteredBackupKeyStatus {
        case .correct:
            return nil
        case .incorrect:
            return nil
        }
    }
    
    var body: some View {
        HStack {
            Spacer()
            Image(systemName: imageSystemName)
                .font(.system(size: 32))
                .foregroundColor(imageColor)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
                if let description {
                    Text(description)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
        }
    }
}


protocol BackupKeyTextFieldActionsProtocol {
    func userEnteredBackupKey(backupKey: String) async
    func userIsTypingBackupKey()
}


private struct BackupKeyTextField: View, SingleTextFieldActions {

    let model: Model
    let actions: BackupKeyTextFieldActionsProtocol
    
    struct Model {
        let showClearButton: Bool
        let acceptableCharactersForBackupKeyString: CharacterSet
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
    }
    
    // SingleTextFieldActions
    
    func tryToPasteTextIfItIsSomeBackupKey(_ receivedText: String) -> Bool {
        let filteredString = receivedText.removingAllCharactersNotInCharacterSet(model.acceptableCharactersForBackupKeyString)
        guard filteredString.count == 32 else {
            return false
        }
        let allStrings = filteredString.byFour.map { String($0) }
        guard allStrings.count == 8 else {
            return false
        }
        let allStringsAreComplete = allStrings.allSatisfy { $0.count == 4 }
        guard allStringsAreComplete else { 
            return false
        }
        textValue0 = allStrings[0]
        textValue1 = allStrings[1]
        textValue2 = allStrings[2]
        textValue3 = allStrings[3]
        textValue4 = allStrings[4]
        textValue5 = allStrings[5]
        textValue6 = allStrings[6]
        textValue7 = allStrings[7]
        indexOfFocusedField = nil
        return true
    }

    
    /// Called by the ``SingleTextField`` at index `index` each time its text value changes.
    fileprivate func singleTextFieldDidChangeAtIndex(_ index: Int) {
        gotoNextTextFieldIfPossible(fromIndex: index)
        if let enteredBackupKey {
            indexOfFocusedField = nil
            Task {
                await actions.userEnteredBackupKey(backupKey: enteredBackupKey)
            }
        } else {
            actions.userIsTypingBackupKey()
        }
    }
    
    
    // Helpers
    
    private func gotoNextTextFieldIfPossible(fromIndex: Int) {
        guard fromIndex < 7 else { return }
        let toIndex = fromIndex + 1
        if textValues[fromIndex].count == 4, textValues[toIndex].count < 4 {
            indexOfFocusedField = toIndex
        }
    }

    /// Returns a 32 characters backup key if the text in the text fields allow to compute one.
    /// Returns `nil` otherwise.
    private var enteredBackupKey: String? {
        let concatenation = textValues
            .reduce("", { $0 + $1 })
            .removingAllCharactersNotInCharacterSet(model.acceptableCharactersForBackupKeyString)
        return concatenation.count == 32 ? concatenation : nil
    }
    

    // Body
    
    var body: some View {
        VStack {
            HStack {
                SingleTextField("X", text: $textValue0, actions: self, model: .init(index: 0, acceptableCharactersForBackupKeyString: model.acceptableCharactersForBackupKeyString))
                SingleTextField("X", text: $textValue1, actions: self, model: .init(index: 1, acceptableCharactersForBackupKeyString: model.acceptableCharactersForBackupKeyString))
                    .focused($indexOfFocusedField, equals: 1)
                SingleTextField("X", text: $textValue2, actions: self, model: .init(index: 2, acceptableCharactersForBackupKeyString: model.acceptableCharactersForBackupKeyString))
                    .focused($indexOfFocusedField, equals: 2)
                SingleTextField("X", text: $textValue3, actions: self, model: .init(index: 3, acceptableCharactersForBackupKeyString: model.acceptableCharactersForBackupKeyString))
                    .focused($indexOfFocusedField, equals: 3)
            }
            HStack {
                SingleTextField("X", text: $textValue4, actions: self, model: .init(index: 4, acceptableCharactersForBackupKeyString: model.acceptableCharactersForBackupKeyString))
                    .focused($indexOfFocusedField, equals: 4)
                SingleTextField("X", text: $textValue5, actions: self, model: .init(index: 5, acceptableCharactersForBackupKeyString: model.acceptableCharactersForBackupKeyString))
                    .focused($indexOfFocusedField, equals: 5)
                SingleTextField("X", text: $textValue6, actions: self, model: .init(index: 6, acceptableCharactersForBackupKeyString: model.acceptableCharactersForBackupKeyString))
                    .focused($indexOfFocusedField, equals: 6)
                SingleTextField("X", text: $textValue7, actions: self, model: .init(index: 7, acceptableCharactersForBackupKeyString: model.acceptableCharactersForBackupKeyString))
                    .focused($indexOfFocusedField, equals: 7)
            }
            if model.showClearButton {
                HStack {
                    Spacer()
                    Button("CLEAR_ALL", action: clearAll)
                }.padding(.top, 4)
            }
        }
    }
    
}


// MARK: - Text field used in this view only


private protocol SingleTextFieldActions {
    func tryToPasteTextIfItIsSomeBackupKey(_ receivedText: String) -> Bool
    func singleTextFieldDidChangeAtIndex(_ index: Int)
}


private struct SingleTextField: View {
    
    private let key: LocalizedStringKey
    private let text: Binding<String>
    private let actions: SingleTextFieldActions
    private let model: Model
    
    struct Model {
        let index: Int // Index of this text field in the BackupKeyTextField
        let acceptableCharactersForBackupKeyString: CharacterSet
    }
    
    @State private var previousText: String? = nil
    
    private static let maxLength = 4
    
    init(_ key: LocalizedStringKey, text: Binding<String>, actions: SingleTextFieldActions, model: Model) {
        self.key = key
        self.text = text
        self.actions = actions
        self.model = model
    }
    
    private let myFont = Font
        .system(size: 18)
        .monospaced()

    var body: some View {
        TextField("XXXX", text: text)
            .textInputAutocapitalization(.characters)
            .textFieldStyle(.roundedBorder)
            .autocorrectionDisabled()
            .multilineTextAlignment(.center)
            .font(myFont)
            .onReceive(Just(text)) { _ in
                guard previousText != text.wrappedValue else { return }
                previousText = text.wrappedValue
                // If the user pastes a backup key, the "text" received here will contain it.
                // To handle this case, we call our "superview" (the BackupKeyTextField) using the
                // tryToPasteTextIfItIsSomeBackupKey method. This method will paste the key in all 8 text
                // fields (including this one) if a key is found. In that case, the method returns true
                // and there is nothing left to do here.
                if actions.tryToPasteTextIfItIsSomeBackupKey(text.wrappedValue) {
                    return
                }
                // If we reach this point, we are not in a situation where the text contains
                // a pasted backup key.
                // We limit the string length to maxLength characters.
                let uppercasedText = text.wrappedValue.uppercased()
                let newText = String(uppercasedText.removingAllCharactersNotInCharacterSet(model.acceptableCharactersForBackupKeyString).prefix(4))
                if text.wrappedValue != newText {
                    text.wrappedValue = newText
                }
                actions.singleTextFieldDidChangeAtIndex(model.index)
            }
    }
    
}



fileprivate extension Collection {
    var byFour: [SubSequence] {
        var startIndex = self.startIndex
        let count = self.count
        let n = count/4 + count % 4
        return (0..<n).map { _ in
            let endIndex = index(startIndex, offsetBy: 4, limitedBy: self.endIndex) ?? self.endIndex
            defer { startIndex = endIndex }
            return self[startIndex..<endIndex]
        }
    }
}


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



struct EnterBackupKeyView_Previews: PreviewProvider {
    
    private final class ActionsForPreviews: EnterBackupKeyViewActionsProtocol {
        func recoverBackupFromEncryptedBackup(_ encryptedBackup: Data, backupKey: String) async throws -> (backupRequestIdentifier: UUID, backupDate: Date) {
            if backupKey == String(repeating: "0", count: 32) {
                return (UUID(), Date())
            } else {
                throw NSError(domain: "EnterBackupKeyView_Previews", code: 0)
            }
        }
        func userWantsToRestoreBackup(backupRequestIdentifier: UUID) async throws {}
    }
    
    
    private static let model = EnterBackupKeyView.Model(encryptedBackup: Data(), acceptableCharactersForBackupKeyString: CharacterSet(charactersIn: "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"))
    
    private static let actions = ActionsForPreviews()
    
    static var previews: some View {
        EnterBackupKeyView(model: model, actions: actions)
    }

}
