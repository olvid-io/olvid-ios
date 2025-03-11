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
import ObvUIObvCircledInitials
import ObvUIObvPhotoButton
import ObvUICoreData
import ObvDesignSystem
import ObvUI


enum GroupInfoViewEditOrCreate {
    case edit
    case create
}


@MainActor
protocol GroupInfoViewModelProtocol: ObservableObject, ObvPhotoButtonViewModelProtocol, HorizontalUsersViewModelProtocol {
    // The circledInitialsConfiguration is part of InitialCircleViewNewModelProtocol
    func updatePhoto(with photo: UIImage?) async
    var selectedUsersOrdered: [UserModel] { get } // Group members
    var initialName: String? { get }
    var initialDescription: String? { get }
    var editOrCreate: GroupInfoViewEditOrCreate { get }
}


protocol GroupInfoViewViewActions: AnyObject {
    func userDidChooseGroupInfos(name: String?, description: String?, photo: UIImage?) async
    // The following two methods leverages the view controller to show
    // the appropriate UI allowing the user to create her profile picture.
    func userWantsToTakePhoto() async -> UIImage?
    func userWantsToChoosePhoto() async -> UIImage?
    func userWantsToChoosePhotoWithDocumentPicker() async -> UIImage?
}


struct GroupInfoView<Model: GroupInfoViewModelProtocol>: View, ObvPhotoButtonViewActionsProtocol {
    
    @ObservedObject var model: Model
    let actions: GroupInfoViewViewActions
    
    init(model: Model, actions: GroupInfoViewViewActions) {
        self.model = model
        self.actions = actions
        self.name = model.initialName ?? ""
        self.description = model.initialDescription ?? ""
    }
    
    @State private var name: String
    @State private var description: String
    @State private var photoAlertToShow: PhotoAlertType?
    @State private var isInterfaceDisabled = false

    
    private enum PhotoAlertType {
        case camera
        case photoLibrary
    }

    
    private func createGroupGroupButtonTapped() {
        withAnimation {
            isInterfaceDisabled = true
        }
        Task { await actions.userDidChooseGroupInfos(name: name, description: description, photo: model.circledInitialsConfiguration.photo) }
    }
    
    
    // PhotoButtonViewActionsProtocol

    func userWantsToAddProfilPictureWithCamera() {
        Task {
            guard let image = await actions.userWantsToTakePhoto() else { return }
            await model.updatePhoto(with: image)
        }
    }
    
    
    func userWantsToAddProfilPictureWithPhotoLibrary() {
        Task {
            guard let image = await actions.userWantsToChoosePhoto() else { return }
            await model.updatePhoto(with: image)
        }
    }

    
    func userWantsToAddProfilePictureWithDocumentPicker() {
        Task {
            guard let image = await actions.userWantsToChoosePhotoWithDocumentPicker() else { return }
            await model.updatePhoto(with: image)
        }
    }
    
    func userWantsToRemoveProfilePicture() {
        Task {
            await model.updatePhoto(with: nil)
        }
    }

    
    private var buttonTitle: LocalizedStringKey {
        switch model.editOrCreate {
        case .edit:
            return "EDIT_GROUP"
        case .create:
            return "CREATE_GROUP"
        }
    }
    
    private let configuration = HorizontalUsersViewConfiguration(textOnEmptySetOfUsers: "", canEditUsers: false)

    var body: some View {
        
        VStack(spacing: 0) {
            
            ScrollView {
                VStack(spacing: 0) {
                    
                    ObvPhotoButtonView(actions: self, model: model, backgroundColor: Color(UIColor.systemGroupedBackground))
                        .disabled(isInterfaceDisabled)

                    VStack(spacing: 6) {
                        
                        HStack {
                            Text("ENTER_GROUP_DETAILS")
                                .font(.footnote)
                                .textCase(.uppercase)
                                .foregroundStyle(.secondary)
                            Spacer(minLength: 0)
                        }.padding(.leading, 30)
                        
                        ObvCardView(shadow: false, cornerRadius: 10) {
                            VStack(spacing: 0) {
                                TextField(LocalizedStringKey("GROUP_NAME"), text: $name)
                                Divider()
                                    .padding(.vertical)
                                TextField(LocalizedStringKey("GROUP_DESCRIPTION"), text: $description)
                            }
                            .disabled(isInterfaceDisabled)
                        }
                        .padding(.horizontal)
                        
                    }.padding(.top, 40)
                    
                    if !model.selectedUsersOrdered.isEmpty {
                        
                        VStack(alignment: .leading, spacing: 0) {
                            
                            HStack(spacing: 2.0) {
                                Text("CHOSEN_MEMBERS")
                                    .textCase(.uppercase)
                                Text(verbatim: "(\(model.selectedUsersOrdered.count))")
                            }
                            .font(.footnote)
                            .foregroundColor(Color(AppTheme.shared.colorScheme.secondaryLabel))
                            .padding(EdgeInsets(top: 0.0, leading: 30.0, bottom: 6.0, trailing: 40.0))
                            
                            HorizontalUsersView(model: model, configuration: configuration, actions: nil)
                                .padding(.horizontal)

                        }
                        .padding(.top, 30)
                        
                    }
                    
                }
                
            }

            VStack {
                OlvidButton(style: .blue, title: Text(buttonTitle), systemIcon: .paperplaneFill, action: createGroupGroupButtonTapped)
                    .disabled(isInterfaceDisabled)
                    .padding()
            }.background(.ultraThinMaterial)

        }
    }
    
}




// MARK: - Previews

struct GroupInfoView_Previews: PreviewProvider {
    
    private final class ActionsForPreviews: GroupInfoViewViewActions {
        
        func userWantsToTakePhoto() async -> UIImage? {
            return UIImage(systemIcon: .checkmarkShield)
            
        }
        
        func userWantsToChoosePhoto() async -> UIImage? {
            return UIImage(systemIcon: .checkmarkSealFill)
        }
        
        func userWantsToChoosePhotoWithDocumentPicker() async -> UIImage? {
            return UIImage(systemIcon: .airpods)
        }

        func userDidChooseGroupInfos(name: String?, description: String?, photo: UIImage?) {}

    }

    private static let actionsForPreviews = ActionsForPreviews()
    
    private final class ModelForPreviews: GroupInfoViewModelProtocol {

        let editOrCreate: GroupInfoViewEditOrCreate = .edit
        let canEditContacts = false
        var photoThatCannotBeRemoved: UIImage? { nil }
        @Published var circledInitialsConfiguration: CircledInitialsConfiguration
        
        let initialName: String? = nil
        let initialDescription: String? = nil

        let selectedUsersOrdered = [PersistedObvContactIdentity]()
        
        init() {
            self.circledInitialsConfiguration = .icon(.person)
        }

        @MainActor
        func updatePhoto(with photo: UIImage?) async {
            if let photo {
                self.circledInitialsConfiguration = .photo(photo: .image(image: photo))
            } else {
                self.circledInitialsConfiguration = .icon(.person)
            }
        }

    }

    private static let modelForPreviews = ModelForPreviews()
    
    static var previews: some View {
        GroupInfoView(model: modelForPreviews, actions: actionsForPreviews)
            .background(Color(.systemGroupedBackground))
            .previewLayout(.sizeThatFits)
    }
}
