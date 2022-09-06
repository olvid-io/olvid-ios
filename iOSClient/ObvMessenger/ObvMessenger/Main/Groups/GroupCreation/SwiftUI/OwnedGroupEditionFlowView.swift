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



final class OwnedGroupEditionFlowViewHostingController: UIHostingController<OwnedGroupEditionFlowView> {

    enum EditionType {
        case create
        case edit
    }

    init(contactGroup: ContactGroup, editionType: EditionType, userConfirmedPublishAction: @escaping () -> Void) {
        let ownedGroupEditionFlowView = OwnedGroupEditionFlowView(contactGroup: contactGroup, userConfirmedPublishAction: userConfirmedPublishAction, editionType: editionType)
        super.init(rootView: ownedGroupEditionFlowView)
        rootView.dismiss = dismiss
    }

    var delegate: GroupEditionDetailsChooserViewControllerDelegate? {
        get { rootView.delegate }
        set { rootView.delegate = newValue }
    }

    @objc required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func dismiss() {
        dismiss(animated: true, completion: nil)
    }

}


struct OwnedGroupEditionFlowView: View {

    @ObservedObject var contactGroup: ContactGroup
    @State private var isPublishActionSheetShown = false
    let userConfirmedPublishAction: () -> Void
    let editionType: OwnedGroupEditionFlowViewHostingController.EditionType
    /// Used to prevent small screen settings when the keyboard appears on a large screen
    @State private var largeScreenUsedOnce = false
    @State private var publishingInProgress = false
    var dismiss: (() -> Void)?
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
        contactGroup.hasChanged && !contactGroup.name.isEmpty
    }

    private var disableCreateGroupButton: Bool {
        delegate?.groupDescriptionDidChange(groupName: contactGroup.name, groupDescription: contactGroup.description, photoURL: contactGroup.photoURL)
        return !canPublish || isPublishActionSheetShown || publishingInProgress
    }

    var buttonTitle: String {
        switch editionType {
        case .create: return NSLocalizedString("CREATE_GROUP", comment: "")
        case .edit: return NSLocalizedString("PUBLISH_GROUP", comment: "")
        }
    }

    var actionTitle: String {
        switch editionType {
        case .create: return NSLocalizedString("PUBLISH_NEW_GROUP", comment: "")
        case .edit: return NSLocalizedString("EDIT_GROUP", comment: "")
        }
    }

    var actionMessage: String {
        switch editionType {
        case .create: return NSLocalizedString("ARE_YOU_SURE_CREATE_NEW_OWNED_GROUP", comment: "")
        case .edit: return NSLocalizedString("ARE_YOU_SURE_PUBLISH_EDITED_OWNED_GROUP", comment: "")
        }
    }

    var actionButton: String {
        switch editionType {
        case .create: return NSLocalizedString("CREATE_MY_GROUP", comment: "")
        case .edit: return NSLocalizedString("PUBLISH_MY_GROUP", comment: "")
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
                                                                                       self.dismiss?()
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
                                isPublishActionSheetShown = true
                            })
                                .padding(.all, 10)
                                .disabled(disableCreateGroupButton)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.all, typicalPadding(for: geometry))
                    Form {
                        Section(header: Text("ENTER_GROUP_DETAILS")) {
                            TextField(LocalizedStringKey("GROUP_NAME"), text: $contactGroup.name)
                            TextField(LocalizedStringKey("GROUP_DESCRIPTION"), text: $contactGroup.description)
                        }.disabled(isPublishActionSheetShown)
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
                OwnedGroupEditionFlowView(contactGroup: $0, userConfirmedPublishAction: {}, editionType: .edit)
            }
        }
    }
}
