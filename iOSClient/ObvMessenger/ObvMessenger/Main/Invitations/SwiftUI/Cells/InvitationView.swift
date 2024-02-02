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
import UI_SystemIcon


protocol InvitationViewModelProtocol: ObservableObject {
    var ownedCryptoId: ObvCryptoId? { get } // Expected to be non-nil
    var title: String { get }
    var titleSystemIcon: SystemIcon? { get }
    var titleSystemIconColor: Color { get }
    var subtitle: String { get }
    var body: String? { get }
    var invitationUUID: UUID { get }
    var sasToExchange: (sasToShow: [Character], onSASInput: ((String) -> ObvDialog?)?)? { get }
    var buttons: [InvitationViewButtonKind] { get }
    var numberOfBadEnteredSas: Int { get }
    var groupMembers: [String] { get }
    var showRedDot: Bool { get }
}


protocol InvitationViewActionsProtocol {
    func userWantsToRespondToDialog(_ obvDialog: ObvDialog) async throws
    func userWantsToAbortProtocol(associatedTo obvDialog: ObvDialog) async throws
    func userWantsToDeleteDialog(_ obvDialog: ObvDialog) async throws
    func userWantsToDiscussWithContact(ownedCryptoId: ObvCryptoId, contactCryptoId: ObvCryptoId) async throws
}


enum InvitationViewButtonKind: Identifiable, Equatable {
    case blueForRespondingToDialog(obvDialog: ObvDialog, localizedTitle: String)
    case plainForRespondingToDialog(obvDialog: ObvDialog, localizedTitle: String, confirmationTitle: LocalizedStringKey?)
    case plainForAbortingProtocol(obvDialog: ObvDialog, localizedTitle: String)
    case plainForDeletingDialog(obvDialog: ObvDialog, localizedTitle: String)
    case discussWithContact(contact: ObvGenericIdentity)
    case spacer
    var id: String {
        switch self {
        case .blueForRespondingToDialog(let obvDialog, let localizedTitle),
                .plainForRespondingToDialog(obvDialog: let obvDialog, localizedTitle: let localizedTitle, _),
                .plainForAbortingProtocol(obvDialog: let obvDialog, localizedTitle: let localizedTitle),
                .plainForDeletingDialog(obvDialog: let obvDialog, localizedTitle: let localizedTitle):
            return [obvDialog.uuid.uuidString, localizedTitle].joined(separator: "|")
        case .discussWithContact(contact: let contact):
            return ["discussWithContact", contact.cryptoId.getIdentity().hexString()].joined(separator: "|")
        case .spacer:
            return UUID().uuidString
        }
    }
}


struct InvitationView<Model: InvitationViewModelProtocol>: View, SASTextFieldActions {
        
    let actions: InvitationViewActionsProtocol
    @ObservedObject var model: Model
    
    @State private var isInterfaceDisabled = false
    @State private var isAbortConfirmationShown = false
    @State private var isRespondingToDialogConfirmationShown = false
    

    private func respondButtonTapped(dialog: ObvDialog) {
        Task {
            do {
                try await actions.userWantsToRespondToDialog(dialog)
            } catch {
                assertionFailure()
            }
        }
    }
    
    
    private func abortButtonTapped(obvDialog: ObvDialog) {
        Task {
            do {
                try await actions.userWantsToAbortProtocol(associatedTo: obvDialog)
            } catch {
                assertionFailure()
            }
        }
    }
    
    
    private func dismissButtonTapped(obvDialog: ObvDialog) {
        Task {
            do {
                try await actions.userWantsToDeleteDialog(obvDialog)
            } catch {
                assertionFailure()
            }
        }
    }
    
    
    private func discussWithContactButtonTapped(contactCryptoId: ObvCryptoId) {
        guard let ownedCryptoId = model.ownedCryptoId else { return }
        Task {
            do {
                try await actions.userWantsToDiscussWithContact(ownedCryptoId: ownedCryptoId, contactCryptoId: contactCryptoId)
            } catch {
                assertionFailure()
            }
        }
    }
    
    // SASTextFieldActions
    
    func userEnteredSAS(in dialog: ObvDialog) {
        isInterfaceDisabled = true
        Task {
            do {
                try await actions.userWantsToRespondToDialog(dialog)
            } catch {
                assertionFailure()
            }
        }
    }
    
    
    func userNeedsToTypeSASAgain() {
        withAnimation {
            isInterfaceDisabled = false
        }
    }
    
    
    // Body
    
    var body: some View {
        VStack {
            
            HStack {
                if let titleSystemIcon = model.titleSystemIcon {
                    Image(systemIcon: titleSystemIcon)
                        .font(.title)
                        .foregroundStyle(model.titleSystemIconColor)
                }
                VStack(alignment: .leading) {
                    Text(model.title)
                        .font(.headline)
                    Text(model.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if model.showRedDot {
                    Image(systemIcon: .circleFill)
                        .foregroundStyle(Color(UIColor.systemRed))
                }
            }
            .padding(.bottom, 4)
            
            if let body = model.body {
                HStack {
                    Text(body)
                        .font(.body)
                        .foregroundStyle(.secondary)
                    Spacer()
                }.padding(.bottom, 4)
            }
            
            if let (sasToShow, onSASInput) = model.sasToExchange {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("YOUR_CODE")
                            .font(.headline)
                        SASTextField(actions: self, model: .init(mode: .showSAS(sas: sasToShow)))
                    }.frame(maxWidth: .infinity)
                    Spacer()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("THEIR_CODE")
                            .font(.headline)
                        if let onSASInput {
                            SASTextField(actions: self, model: .init(mode: .enterSAS(numberOfBadEnteredSAS: model.numberOfBadEnteredSas, onSASInput: onSASInput)))
                        } else {
                            SASTextField(actions: self, model: .init(mode: .showCheckMark))
                        }
                    }.frame(maxWidth: .infinity)
                }.padding(.top)
            }
            
            if !model.groupMembers.isEmpty {
                VStack(alignment: .leading) {
                    HStack {
                        Text("\(model.groupMembers.count)_GROUP_MEMBERS")
                            .font(.subheadline)
                        Spacer()
                    }
                    ForEach(model.groupMembers) { groupMember in
                        Text(verbatim: ["·", groupMember].joined(separator: " "))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            HStack {
                Spacer()
                ForEach(model.buttons) { button in
                    switch button {
                        
                    case .plainForRespondingToDialog(obvDialog: let obvDialog, localizedTitle: let localizedTitle, confirmationTitle: let confirmationTitle):
                        if let confirmationTitle {
                            Button(action: { isRespondingToDialogConfirmationShown = true }, label: {
                                Text(verbatim: localizedTitle)
                            })
                            .confirmationDialog(confirmationTitle, isPresented: $isRespondingToDialogConfirmationShown, titleVisibility: .visible) {
                                Button("YES", action: { respondButtonTapped(dialog: obvDialog) })
                                Button("NO", role: .cancel, action: {})
                            }
                        } else {
                            Button(action: { respondButtonTapped(dialog: obvDialog) }, label: {
                                Text(verbatim: localizedTitle)
                            })
                        }
                        
                    case .blueForRespondingToDialog(obvDialog: let obvDialog, localizedTitle: let localizedTitle):
//                        if let confirmationLocalizedTitle {
//                            BlueButtonView(localizedTitle, action: { isRespondingConfirmationShown = true })
//                                .confirmationDialog(confirmationLocalizedTitle, isPresented: $isRespondingConfirmationShown, titleVisibility: .visible) {
//                                    Button("YES") {
//                                        respondButtonTapped(obvDialog: obvDialog)
//                                    }
//                                    Button("NO", role: .cancel, action: {})
//                                }
//                        } else {
                            BlueButtonView(localizedTitle, action: { respondButtonTapped(dialog: obvDialog) })
  //                      }
                        
                    case .plainForAbortingProtocol(obvDialog: let obvDialog, localizedTitle: let localizedTitle):
                        Button(action: { isAbortConfirmationShown = true }, label: { Text(verbatim: localizedTitle) })
                            .confirmationDialog("ARE_YOU_SURE_YOU_WANT_TO_ABORT", isPresented: $isAbortConfirmationShown, titleVisibility: .visible) {
                                Button("YES") { abortButtonTapped(obvDialog: obvDialog) }
                                Button("NO", role: .cancel, action: {})
                            }
                        
                    case .plainForDeletingDialog(obvDialog: let obvDialog, localizedTitle: let localizedTitle):
                        Button(action: { dismissButtonTapped(obvDialog: obvDialog) }, label: { Text(verbatim: localizedTitle) })
                        
                    case .discussWithContact(contact: let contact):
                        OtherBlueButtonView("DISCUSS_WITH_\(contact.currentIdentityDetails.coreDetails.getDisplayNameWithStyle(.short))", action: { discussWithContactButtonTapped(contactCryptoId: contact.cryptoId) })
                        
                    case .spacer:
                        Spacer()
                        
                    }
                }
            }
            
        }
        .disabled(isInterfaceDisabled)
        .onChange(of: model.buttons) { _ in
            isInterfaceDisabled = false
        }
    }
}


protocol SASTextFieldActions {
    func userEnteredSAS(in dialog: ObvDialog)
    func userNeedsToTypeSASAgain()
}


private struct SASTextField: View, SingleSASDigitTextFielddActions {
    
    let actions: SASTextFieldActions
    let model: Model
    
    @State private var shownAlert: AlertKind = .badSAS
    @State private var isAlertShown = false
        
    private enum AlertKind {
        case badSAS
    }

    enum Mode {
        case showSAS(sas: [Character])
        case enterSAS(numberOfBadEnteredSAS: Int, onSASInput: (String) -> ObvDialog?)
        case showCheckMark
    }

    struct Model {
        let mode: Mode
    }

    @State private var textValue0: String = ""
    @State private var textValue1: String = ""
    @State private var textValue2: String = ""
    @State private var textValue3: String = ""

    private var textValues: [String] {
        [textValue0, textValue1, textValue2, textValue3]
    }

    @FocusState private var indexOfFocusedField: Int?

    private func clearAll() {
        textValue0 = ""
        textValue1 = ""
        textValue2 = ""
        textValue3 = ""
        indexOfFocusedField = nil
    }

    
    private var showClearButton: Bool {
        switch model.mode {
        case .enterSAS:
            return true
        case .showSAS, .showCheckMark:
            return false
        }
    }
    
    // SingleTextFieldActions
    
    /// Called by the ``SingleTextField`` at index `index` each time its text value changes.
    func singleTextFieldDidChangeAtIndex(_ index: Int) {
        switch model.mode {
        case .showSAS, .showCheckMark:
            return
        case .enterSAS(numberOfBadEnteredSAS: _, onSASInput: let onSASInput):
            gotoNextTextFieldIfPossible(fromIndex: index)
            if let enteredSAS {
                indexOfFocusedField = nil
                guard let obvDialog = onSASInput(enteredSAS) else { return }
                actions.userEnteredSAS(in: obvDialog)
            }
        }
    }

    // Helpers
    
    /// Returns an 4 characters SAS if the texts in the text fields allow to compute one.
    /// Returns `nil` otherwise.
    private var enteredSAS: String? {
        let concatenation = textValues
            .reduce("", { $0 + $1 })
            .removingAllCharactersNotInCharacterSet(.decimalDigits)
        return concatenation.count == 4 ? concatenation : nil
    }

    private func gotoNextTextFieldIfPossible(fromIndex: Int) {
        guard fromIndex < 3 else { return }
        let toIndex = fromIndex + 1
        if textValues[fromIndex].count == 1, textValues[toIndex].count < 1 {
            indexOfFocusedField = toIndex
        }
    }
    
    
    private var isCheckMarkShown: Bool {
        switch model.mode {
        case .showSAS, .enterSAS:
            return false
        case .showCheckMark:
            return true
        }
    }
    
    private var numberOfBadEnteredSAS: Int {
        switch model.mode {
        case .showSAS, .showCheckMark:
            return 0
        case .enterSAS(let numberOfBadEnteredSAS, _):
            return numberOfBadEnteredSAS
        }
    }
    
    private func alertOkButtonTapped() {
        clearAll()
        actions.userNeedsToTypeSASAgain()
    }

    // Body
    
    var body: some View {
        VStack {
            HStack(spacing: 0) {
                
                switch model.mode {
                    
                case .showSAS(let sas):
                    ForEach((0..<sas.count), id: \.self) { index in
                        SingleSASDigitTextField("", text: .constant("\(sas[index])"), actions: nil, model: nil)
                            .disabled(true)
                    }

                case .showCheckMark:
                    ForEach(0..<4, id: \.self) { index in
                        SingleSASDigitTextField("", text: .constant("0"), actions: nil, model: nil)
                            .disabled(true)
                            .opacity(0.0)
                    }
                    .opacity(isCheckMarkShown ? 0 : 1)

                case .enterSAS:
                    SingleSASDigitTextField("X", text: $textValue0, actions: self, model: .init(index: 0))
                    SingleSASDigitTextField("X", text: $textValue1, actions: self, model: .init(index: 1))
                        .focused($indexOfFocusedField, equals: 1)
                    SingleSASDigitTextField("X", text: $textValue2, actions: self, model: .init(index: 2))
                        .focused($indexOfFocusedField, equals: 2)
                    SingleSASDigitTextField("X", text: $textValue3, actions: self, model: .init(index: 3))
                        .focused($indexOfFocusedField, equals: 3)
                }
            }
            .overlay {
                Image(systemIcon: .checkmarkCircleFill)
                    .font(.system(size: 32))
                    .foregroundStyle(Color(UIColor.systemGreen))
                    .opacity(isCheckMarkShown ? 1.0 : 0.0)
            }
            if showClearButton {
                HStack {
                    Spacer()
                    Button("CLEAR_ALL", action: clearAll)
                }
                .padding(.top, 2)
            }
        }
        .onChange(of: numberOfBadEnteredSAS) { _ in
            isAlertShown = true
        }
        .alert(isPresented: $isAlertShown) {
            switch shownAlert {
            case .badSAS:
                return Alert(title: Text("Incorrect code"),
                      message: Text("The core you entered is incorrect. The code you need to enter is the one displayed on your contact's device."),
                             dismissButton: .default(Text("Ok"), action: alertOkButtonTapped))
            }
        }
    }
    
}


protocol SingleSASDigitTextFielddActions {
    func singleTextFieldDidChangeAtIndex(_ index: Int)
}



struct SingleSASDigitTextField: View {
    
    private let key: LocalizedStringKey
    private let text: Binding<String>
    private let actions: SingleSASDigitTextFielddActions? // Not needed when the this text field stays disabled
    private let model: Model? // Not needed when the this text field stays disabled
    
    @Environment(\.isEnabled) var isEnabled
    
    struct Model {
        let index: Int // Index of this text field in the BackupKeyTextField
    }
    
    @State private var previousText: String? = nil
    
    private static let maxLength = 1
    
    /// Both `actions` and `model` must be set, unless this text field is disabled by default (just used to show some existing value).
    init(_ key: LocalizedStringKey, text: Binding<String>, actions: SingleSASDigitTextFielddActions?, model: Model?) {
        self.key = key
        self.text = text
        self.actions = actions
        self.model = model
    }
    
    private let myFont = Font
        .system(size: 18)
        .monospaced()
        .weight(.bold)

    var body: some View {
        TextField(key, text: text)
            .keyboardType(.decimalPad)
            .textContentType(.none)
            .multilineTextAlignment(.center)
            .font(myFont)
            .padding(.vertical, 8)
            .overlay(content: {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(UIColor.systemGray2), lineWidth: 1)
                    .padding(.horizontal, 1)
            })
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(UIColor.systemGray5))
                    .padding(.horizontal, 1)
                    .opacity(isEnabled ? 0 : 1)
            )
            .onReceive(Just(text)) { _ in
                guard let actions, let model else { return }
                guard previousText != text.wrappedValue else { return }
                previousText = text.wrappedValue
                // We limit the string length to maxLength characters.
                let newText = String(text.wrappedValue.removingAllCharactersNotInCharacterSet(.decimalDigits).prefix(Self.maxLength))
                if text.wrappedValue != newText {
                    text.wrappedValue = newText
                }
                actions.singleTextFieldDidChangeAtIndex(model.index)
            }
    }
    
}






// MARK: - Button used in this view only

private struct OtherBlueButtonView: View {
    
    private let action: () -> Void
    private let key: LocalizedStringKey

    @Environment(\.isEnabled) var isEnabled
    
    init(_ key: LocalizedStringKey, action: @escaping () -> Void) {
        self.key = key
        self.action = action
    }
        
    var body: some View {
        Button(action: action) {
            Text(key)
                .foregroundStyle(.white)
                .padding()
        }
        .background(Color("Blue01"))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .opacity(isEnabled ? 1.0 : 0.6)
    }
    
}


private struct BlueButtonView: View {
    
    private let action: () -> Void
    private let localizedTitle: String

    @Environment(\.isEnabled) var isEnabled
    
    init(_ localizedTitle: String, action: @escaping () -> Void) {
        self.localizedTitle = localizedTitle
        self.action = action
    }
        
    var body: some View {
        Button(action: action) {
            Text(verbatim: localizedTitle)
                .foregroundStyle(.white)
                .padding()
        }
        .background(Color("Blue01"))
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

struct InvitationView_Previews: PreviewProvider {
    
    private static let ownedCryptoId = try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f0000b82ae0c57e570389cb03d5ad93dab4606bda7bbe01c09ce5e423094a8603a61e01693046e10e04606ef4461d31e1aa1819222a0a606a250e91749095a4410778c1")!)

    private static let otherCryptoId = try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f0000b82ae0c57e570389cb03d5ad93dab4606bda7bbe01c09ce5e423094a8603a61e01693046e10e04606ef4461d31e1aa1819222a0a606a250e91749095a4410778c1")!)

    private final class ModelForPreviews: InvitationViewModelProtocol {
                
        @Published var numberOfBadEnteredSas = 0
        
        private static let someDialog = ObvDialog(
            uuid: UUID(),
            encodedElements: 0.obvEncode(),
            ownedCryptoId: InvitationView_Previews.ownedCryptoId,
            category: .acceptInvite(contactIdentity: .init(
                cryptoId: otherCryptoId,
                currentIdentityDetails: .init(coreDetails: try! .init(firstName: "Steve",
                                                                      lastName: "Jobs",
                                                                      company: nil,
                                                                      position: nil,
                                                                      signedUserDetails: nil),
                                              photoURL: nil))))
        
        let ownedCryptoId: ObvCryptoId? = InvitationView_Previews.ownedCryptoId
        let title = "Invitation title"
        let subtitle = "Invitation subtitle"
        let body: String? = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Aliquam placerat dignissim nulla. Nullam sed felis nec purus maximus ultricies vitae non mauris. Maecenas quis volutpat lectus."
        let invitationUUID = UUID()
        var sasToExchange: (sasToShow: [Character], onSASInput: ((String) -> ObvTypes.ObvDialog?)?)? {
            let sasToShow = "1234".map { $0 }
            let onSASInput: (String) -> ObvTypes.ObvDialog? = { inputSAS in
                guard inputSAS == "0000" else {
                    self.numberOfBadEnteredSas += 1
                    return nil
                }
                return Self.someDialog
            }
            return (sasToShow, onSASInput)
        }

        var buttons: [InvitationViewButtonKind] {
            return [
                .plainForAbortingProtocol(obvDialog: Self.someDialog, localizedTitle: "Abort"),
                .spacer,
            ]
        }
        
        var groupMembers: [String] {
            ["Steve Jobs", "Tim Cook"]
        }
        
        var showRedDot: Bool { true }
        
        var titleSystemIcon: SystemIcon? { return .person }
        
        var titleSystemIconColor: Color { Color(UIColor.systemCyan) }
        
    }
    
    private static let model = ModelForPreviews()
    
    final class ActionsForPreviews: InvitationViewActionsProtocol {
        func userWantsToAbortProtocol(associatedTo obvDialog: ObvTypes.ObvDialog) async throws {}
        func userWantsToRespondToDialog(_ obvDialog: ObvDialog) {}
        func userWantsToDeleteDialog(_ obvDialog: ObvDialog) async throws {}
        func userWantsToDiscussWithContact(ownedCryptoId: ObvCryptoId, contactCryptoId: ObvCryptoId) async throws {}
    }

    private static let actions = ActionsForPreviews()
    
    static var previews: some View {
        InvitationView(actions: actions, model: model)
            .previewLayout(PreviewLayout.sizeThatFits)
            .padding()
            .previewDisplayName("InvitationView")
    }
    
}
