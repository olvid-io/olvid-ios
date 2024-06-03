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
import ObvUICoreData


protocol ContactsSelectionForGroupViewActions: AnyObject {
    func userDidValidateSelectedContacts(selectedContacts: [PersistedObvContactIdentity]) async
}


struct ContactsSelectionForGroupView: View {
            
    @ObservedObject public var viewModel: GroupContactsViewModel
    let actions: ContactsSelectionForGroupViewActions
    
    private func userWantsToSave() {
        let selectedContacts = viewModel.orderedContacts
        Task {
            await actions.userDidValidateSelectedContacts(selectedContacts: selectedContacts)
        }
    }

    var body: some View {
        VStack {
            
            HorizontalContactsView(model: viewModel, actions: viewModel)
                .padding(EdgeInsets(top: 30.0, leading: 20.0, bottom: 0.0, trailing: 20.0))
            
            ContactsView(store: viewModel.store)
            
            VStack {
                OlvidButton(style: .blue,
                            title: Text(CommonString.Word.Next),
                            systemIcon: .personCropCircleFillBadgeCheckmark,
                            action: userWantsToSave)
                    .padding()
                    .background(.ultraThinMaterial)
            }
            
        }
    }
    
}
