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
import ObvTypes
import ObvUIObvPhotoButton
import ObvUIObvCircledInitials
import ObvUI
import ObvDesignSystem



protocol EditNicknameAndCustomPictureViewActionsProtocol: AnyObject {
    func userWantsToSaveNicknameAndCustomPicture(identifier: EditNicknameAndCustomPictureView.Model.IdentifierKind, nickname: String, customPhoto: UIImage?) async
    func userWantsToDismissEditNicknameAndCustomPictureView() async
    // The following two methods leverages the view controller to show
    // the appropriate UI allowing the user to create her profile picture.
    func userWantsToTakePhoto() async -> UIImage?
    func userWantsToChoosePhoto() async -> UIImage?
    func userWantsToChoosePhotoWithDocumentPicker() async -> UIImage?
}



// MARK: - EditNicknameAndCustomPictureView

struct EditNicknameAndCustomPictureView: View, ObvPhotoButtonViewActionsProtocol {
    
    
    final class Model: ObservableObject, ObvPhotoButtonViewModelProtocol {
        
        enum IdentifierKind {
            case contact(contactIdentifier: ObvContactIdentifier)
            case groupV2(groupV2Identifier: GroupV2Identifier)
        }
        
        fileprivate let identifier: IdentifierKind
        fileprivate let currentNickname: String // Empty string means "no nickname"
        fileprivate let currentInitials: String
        fileprivate let defaultPhoto: UIImage? // The photo chosen by the contact or by a group owner
        fileprivate let currentCustomPhoto: UIImage?
        
        var photoThatCannotBeRemoved: UIImage? {
            defaultPhoto
        }

        @Published var circledInitialsConfiguration: CircledInitialsConfiguration
        
        init(identifier: IdentifierKind, currentInitials: String, defaultPhoto: UIImage?, currentCustomPhoto: UIImage?, currentNickname: String) {
            self.identifier = identifier
            self.currentInitials = currentInitials
            self.currentNickname = currentNickname
            self.defaultPhoto = defaultPhoto
            self.currentCustomPhoto = currentCustomPhoto
            let photo = currentCustomPhoto ?? defaultPhoto
            switch identifier {
            case .contact(let contactIdentifier):
                self.circledInitialsConfiguration = .contact(
                    initial: currentInitials,
                    photo: .image(image: photo),
                    showGreenShield: false,
                    showRedShield: false,
                    cryptoId: contactIdentifier.contactCryptoId,
                    tintAdjustementMode: .normal)
            case .groupV2(let groupV2Identifier):
                self.circledInitialsConfiguration = .groupV2(
                    photo: .image(image: photo),
                    groupIdentifier: groupV2Identifier,
                    showGreenShield: false)
            }
        }
        
        
        /// When the user choses a new photo:
        /// - If it is non-`nil`, we show it and this is the one that will be saved as a custom photo if the user hits the save button
        /// - If it is `nil`, we consider that the user wants to remove the current custom photo (if any) and show the default photo chosen by the contact or a group owner
        @MainActor
        fileprivate func userChoseNewCustomPhoto(_ customPhoto: UIImage?) async {
            let photo = customPhoto ?? self.defaultPhoto
            withAnimation {
                self.circledInitialsConfiguration = self.circledInitialsConfiguration.replacingPhoto(with: .image(image: photo))
            }
        }
        
        
        @MainActor
        fileprivate func userChoseNewNickname(_ nickname: String) async {
            let sanitizedNickname = nickname.trimmingWhitespacesAndNewlines()
            let newInitials: String
            if let firstCharacter = sanitizedNickname.first {
                newInitials = String(firstCharacter)
            } else {
                newInitials = currentInitials
            }
            withAnimation {
                self.circledInitialsConfiguration = circledInitialsConfiguration.replacingInitials(with: newInitials)
            }
        }
        
    }
    

    let actions: EditNicknameAndCustomPictureViewActionsProtocol
    @ObservedObject var model: Model
    @State private var nickname = ""
    @State private var isSaveButtonDisabled = true
    
    
    private func userWantsToSaveNicknameAndCustomPicture() {
        Task {
            let customPhoto: UIImage?
            if model.circledInitialsConfiguration.photo != model.defaultPhoto {
                customPhoto = model.circledInitialsConfiguration.photo
            } else {
                customPhoto = nil
            }
            await actions.userWantsToSaveNicknameAndCustomPicture(identifier: model.identifier,
                                                                  nickname: nickname.trimmingWhitespacesAndNewlines(),
                                                                  customPhoto: customPhoto)
        }
    }
    
    
    private func userWantsToCancel() {
        Task {
            await actions.userWantsToDismissEditNicknameAndCustomPictureView()
        }
    }
 
    
    private func nicknameDidChange() {
        Task {
            await model.userChoseNewNickname(nickname)
            resetIsSaveButtonDisabled()
        }
    }
    

    private func onAppear() {
        self.nickname = model.currentNickname
    }

    
    private func resetIsSaveButtonDisabled() {
        let nicknameChanged = nickname != model.currentNickname
        let customPhotoChanged: Bool
        if let currentCustomPhoto = model.currentCustomPhoto {
            customPhotoChanged = model.circledInitialsConfiguration.photo != currentCustomPhoto
        } else if let defaultPhoto = model.defaultPhoto {
            customPhotoChanged = model.circledInitialsConfiguration.photo != defaultPhoto
        } else {
            customPhotoChanged = model.circledInitialsConfiguration.photo != nil
        }
        withAnimation {
            isSaveButtonDisabled = !nicknameChanged && !customPhotoChanged
        }
    }
    
    // ObvPhotoButtonViewActionsProtocol
    
    func userWantsToAddProfilPictureWithCamera() {
        Task {
            guard let newImage = await actions.userWantsToTakePhoto() else { return }
            await model.userChoseNewCustomPhoto(newImage)
            resetIsSaveButtonDisabled()
        }
    }
    
    
    func userWantsToAddProfilPictureWithPhotoLibrary() {
        Task {
            guard let newImage = await actions.userWantsToChoosePhoto() else { return }
            await model.userChoseNewCustomPhoto(newImage)
            resetIsSaveButtonDisabled()
        }
    }
    
    
    func userWantsToRemoveProfilePicture() {
        Task {
            await model.userChoseNewCustomPhoto(nil)
            resetIsSaveButtonDisabled()
        }
    }
    
    
    func userWantsToAddProfilePictureWithDocumentPicker() {
        Task {
            guard let newImage = await actions.userWantsToChoosePhotoWithDocumentPicker() else { return }
            await model.userChoseNewCustomPhoto(newImage)
            resetIsSaveButtonDisabled()
        }
    }
    
    
    private var explanationLocalizedStringKey: LocalizedStringKey {
        switch model.identifier {
        case .contact:
            return "EDIT_NICKNAME_AND_CUSTOM_PICTURE_EXPLANATION_FOR_CONTACT"
        case .groupV2:
            return "EDIT_NICKNAME_AND_CUSTOM_PICTURE_EXPLANATION_FOR_GROUP"
        }
    }
    
    
    var body: some View {
        VStack {
            ScrollView {
                VStack {
                    Text("EDIT_NICKNAME_AND_CUSTOM_PICTURE")
                        .font(.title)
                        .fontWeight(.heavy)
                        .multilineTextAlignment(.center)
                        .padding(.bottom)
                    Text(explanationLocalizedStringKey)
                        .padding(.bottom)
                        .multilineTextAlignment(.center)
                    ObvPhotoButtonView(actions: self, model: model)
                        .padding(.bottom, 10)
                    InternalTextField("FORM_NICKNAME", text: $nickname)
                        .onChange(of: nickname) { _ in nicknameDidChange() }
                        .padding(.bottom, 10)
                }
                .padding()
            }
            VStack {
                OlvidButton(style: .blue, title: Text("Save"), systemIcon: nil, action: userWantsToSaveNicknameAndCustomPicture)
                    .disabled(isSaveButtonDisabled)
                OlvidButton(style: .text, title: Text("Cancel"), systemIcon: nil, action: userWantsToCancel)
            }.padding()
        }
        .onAppear(perform: onAppear)
    }
}


// MARK: - Text field used in this view only

private struct InternalTextField: View {
    
    private let key: LocalizedStringKey
    private let text: Binding<String>
    
    init(_ key: LocalizedStringKey, text: Binding<String>) {
        self.key = key
        self.text = text
    }
    
    var body: some View {
        TextField(key, text: text)
            .padding()
            .background(Color("TextFieldBackgroundColor"))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
}



// MARK: - Previews


struct EditNicknameAndCustomPictureView_Previews: PreviewProvider {
    
    private static let ownedCryptoId = try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f0000b82ae0c57e570389cb03d5ad93dab4606bda7bbe01c09ce5e423094a8603a61e01693046e10e04606ef4461d31e1aa1819222a0a606a250e91749095a4410778c1")!)
    private static let contactCryptoId = try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f000009e171a9c73a0d6e9480b022154c83b13dfa8e4c99496c061c0c35b9b0432b3a014a5393f98a1aead77b813df0afee6b8af7e5f9a5aae6cb55fdb6bc5cc766f8da")!)

    private static let contactIdentifier = ObvContactIdentifier(contactCryptoId: contactCryptoId, ownedCryptoId: ownedCryptoId)

    private final class ActionsForPreviews: EditNicknameAndCustomPictureViewActionsProtocol {
        
        func userWantsToSaveNicknameAndCustomPicture(identifier: EditNicknameAndCustomPictureView.Model.IdentifierKind, nickname: String, customPhoto: UIImage?) async {}
        func userWantsToDismissEditNicknameAndCustomPictureView() async {}
        
        func userWantsToTakePhoto() async -> UIImage? {
            return UIImage(systemIcon: .archivebox)
        }
        
        func userWantsToChoosePhoto() async -> UIImage? {
            return UIImage(systemIcon: .book)
        }
     
        func userWantsToChoosePhotoWithDocumentPicker() async -> UIImage? {
            return UIImage(systemIcon: .airpods)
        }
        
    }
    
    private static let actions = ActionsForPreviews()
    
    private static let model = EditNicknameAndCustomPictureView.Model(
        identifier: .contact(contactIdentifier: contactIdentifier),
        currentInitials: "A",
        defaultPhoto: UIImage(systemIcon: .alarm),
        currentCustomPhoto: nil,
        currentNickname: "") // Empty string means "no nickname"
    
    static var previews: some View {
        EditNicknameAndCustomPictureView(actions: actions, model: model)
    }
    
}
