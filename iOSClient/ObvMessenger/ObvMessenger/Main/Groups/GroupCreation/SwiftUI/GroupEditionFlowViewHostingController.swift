/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
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



final class GroupEditionFlowViewHostingController: UIHostingController<OwnedGroupEditionFlowView> {

    enum EditionType {
        case createGroupV1
        case createGroupV2
        case editGroupV1 // Always as admin
        case editGroupV2AsAdmin
        case editGroupV2CustomNameAndCustomPhoto
    }

    init(contactGroup: ContactGroup, editionType: EditionType, userConfirmedPublishAction: @escaping () -> Void) {
        let ownedGroupEditionFlowView = OwnedGroupEditionFlowView(contactGroup: contactGroup, userConfirmedPublishAction: userConfirmedPublishAction, editionType: editionType)
        super.init(rootView: ownedGroupEditionFlowView)
    }

    var delegate: GroupEditionDetailsChooserViewControllerDelegate? {
        get { rootView.delegate }
        set { rootView.delegate = newValue }
    }

    @objc required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

}


struct OwnedGroupEditionFlowView: View {

    @ObservedObject var contactGroup: ContactGroup
    @State private var isPublishActionSheetShown = false
    let userConfirmedPublishAction: () -> Void
    let editionType: GroupEditionFlowViewHostingController.EditionType
    /// Used to prevent small screen settings when the keyboard appears on a large screen
    @State private var largeScreenUsedOnce = false
    @State private var publishingInProgress = false
    weak var delegate: GroupEditionDetailsChooserViewControllerDelegate?

    private func useSmallScreenMode(for geometry: GeometryProxy) -> Bool {
        if largeScreenUsedOnce { return false }
        let res = max(geometry.size.height, geometry.size.width) < 510
        if !res {
            DispatchQueue.main.async {
                largeScreenUsedOnce = true
            }
        }
        return res
    }

    private func typicalPadding(for geometry: GeometryProxy) -> CGFloat {
        useSmallScreenMode(for: geometry) ? 8 : 16
    }

    private var canPublish: Bool {
        switch editionType {
        case .createGroupV1:
            return contactGroup.hasChanged && !contactGroup.name.isEmpty
        case .createGroupV2:
            return true
        case .editGroupV1:
            return contactGroup.hasChanged
        case .editGroupV2AsAdmin:
            return contactGroup.hasChanged
        case .editGroupV2CustomNameAndCustomPhoto:
            return contactGroup.hasChanged
        }
    }

    private var disableCreateGroupButton: Bool {
        delegate?.groupDescriptionDidChange(groupName: contactGroup.name, groupDescription: contactGroup.description, photoURL: contactGroup.photoURL)
        return !canPublish || isPublishActionSheetShown || publishingInProgress
    }

    var buttonTitle: String {
        switch editionType {
        case .createGroupV1, .createGroupV2: return NSLocalizedString("CREATE_GROUP", comment: "")
        case .editGroupV1, .editGroupV2AsAdmin: return NSLocalizedString("PUBLISH_GROUP", comment: "")
        case .editGroupV2CustomNameAndCustomPhoto: return NSLocalizedString("SAVE_CUSTOM_GROUP_VALUES", comment: "")
        }
    }

    var actionTitle: String {
        switch editionType {
        case .createGroupV1, .createGroupV2: return NSLocalizedString("PUBLISH_NEW_GROUP", comment: "")
        case .editGroupV1, .editGroupV2AsAdmin, .editGroupV2CustomNameAndCustomPhoto: return NSLocalizedString("EDIT_GROUP", comment: "")
        }
    }

    var actionMessage: String {
        switch editionType {
        case .createGroupV1, .createGroupV2: return NSLocalizedString("ARE_YOU_SURE_CREATE_NEW_OWNED_GROUP", comment: "")
        case .editGroupV1, .editGroupV2AsAdmin: return NSLocalizedString("ARE_YOU_SURE_PUBLISH_EDITED_OWNED_GROUP", comment: "")
        case .editGroupV2CustomNameAndCustomPhoto: assertionFailure(); return ""
        }
    }

    var actionButton: String {
        switch editionType {
        case .createGroupV1, .createGroupV2: return NSLocalizedString("CREATE_MY_GROUP", comment: "")
        case .editGroupV1, .editGroupV2AsAdmin: return NSLocalizedString("PUBLISH_MY_GROUP", comment: "")
        case .editGroupV2CustomNameAndCustomPhoto: assertionFailure(); return ""
        }
    }

    var body: some View {
        ZStack {
            Color(AppTheme.shared.colorScheme.systemBackground)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .edgesIgnoringSafeArea(.all)
            GeometryReader { geometry in
                VStack(alignment: .leading, spacing: 0) {
                    ObvCardView(padding: 0) {
                        VStack(spacing: 0) {
                            HStack {
                                GroupCardContentView(model: contactGroup,
                                                     editionMode: contactGroup.editPictureMode)
                                    .padding(.horizontal, typicalPadding(for: geometry))
                                    .padding(.top, typicalPadding(for: geometry))
                                    .padding(.bottom, typicalPadding(for: geometry))
                                    .actionSheet(isPresented: $isPublishActionSheetShown) {
                                        ActionSheet(title: Text(actionTitle),
                                                    message: Text(actionMessage),
                                                    buttons: [
                                                        ActionSheet.Button.default(Text(actionButton),
                                                                                   action: {
                                                                                       publishingInProgress = true
                                                                                       userConfirmedPublishAction() }),
                                                        ActionSheet.Button.cancel(),
                                                    ])
                                    }
                                Spacer()
                            }
                            OlvidButton(style: .blue,
                                        title: Text(buttonTitle),
                                        systemIcon: .paperplaneFill,
                                        action: {
                                switch editionType {
                                case .createGroupV1, .createGroupV2, .editGroupV1, .editGroupV2AsAdmin:
                                    isPublishActionSheetShown = true
                                case .editGroupV2CustomNameAndCustomPhoto:
                                    publishingInProgress = true
                                    userConfirmedPublishAction()
                                }
                            })
                                .padding(.all, 10)
                                .disabled(disableCreateGroupButton)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.all, typicalPadding(for: geometry))
                    Form {
                        switch editionType {
                        case .createGroupV1, .createGroupV2, .editGroupV1, .editGroupV2AsAdmin:
                            Section(header: Text("ENTER_GROUP_DETAILS")) {
                                TextField(LocalizedStringKey("GROUP_NAME"), text: $contactGroup.name)
                                TextField(LocalizedStringKey("GROUP_DESCRIPTION"), text: $contactGroup.description)
                            }.disabled(isPublishActionSheetShown)
                        case .editGroupV2CustomNameAndCustomPhoto:
                            Section(header: Text("CHOOSE_GROUP_NICKNAME")) {
                                TextField(LocalizedStringKey("FORM_NICKNAME"), text: $contactGroup.name)
                            }.disabled(isPublishActionSheetShown)
                        }
                        if !contactGroup.members.isEmpty {
                            Section(header: Text("CHOSEN_GROUP_MEMBERS")) {
                                VStack {
                                    ForEach(contactGroup.members.sorted(by: { $0.firstName < $1.firstName }), id: \.id) { member in
                                        HStack {
                                            IdentityCardContentView(model: member,
                                                                    displayMode: .small,
                                                                    editionMode: .none)
                                            Spacer(minLength: 0)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Spacer()
                }
            }
        }
    }
}


struct OwnedGroupEditionFlowView_Previews: PreviewProvider {

    static var previews: some View {
        Group {
            ForEach(IdentityCardContentView_Previews.groups) {
                OwnedGroupEditionFlowView(contactGroup: $0, userConfirmedPublishAction: {}, editionType: .editGroupV1)
            }
        }
    }
}
