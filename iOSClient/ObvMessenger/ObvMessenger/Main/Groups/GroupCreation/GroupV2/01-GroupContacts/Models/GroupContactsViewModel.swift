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
import ObvTypes
import ObvUICoreData


final class GroupContactsViewModel: ObservableObject, HorizontalContactsViewModelProtocol, MultiContactChooserViewControllerDelegate, SingleContactViewActionsProtocol {

    @Published private(set) var selectedContacts: Set<PersistedObvContactIdentity>
    @Published private(set) var orderedContacts: [PersistedObvContactIdentity]

    let canEditContacts = true
    
    let store: ContactsViewStore
    
    init(store: ContactsViewStore, preSelectedContacts: Set<PersistedObvContactIdentity>) {
        self.orderedContacts = Array(preSelectedContacts).sorted(by: \.customOrShortDisplayName)
        self.selectedContacts = preSelectedContacts
        self.store = store
        self.store.multiContactChooserDelegate = self
    }
    

    // MARK: - MultiContactChooserViewControllerDelegate
    
    func userDidSelect(_ contact: ObvUICoreData.PersistedObvContactIdentity) {
        
        if !selectedContacts.contains(contact) {
            selectedContacts.insert(contact)
            store.changed.toggle()
        }
        
        if orderedContacts.first(where: { $0.cryptoId == contact.cryptoId }) == nil {
            orderedContacts.insert(contact, at: 0)
        }
        
    }
    
    func userDidDeselect(_ contact: ObvUICoreData.PersistedObvContactIdentity) {
        
        let contactCryptoId = contact.cryptoId
        Task { await userWantsToDeleteContact(cryptoId: contactCryptoId) }
                
    }
    
    func setUserContactSelection(to contacts: Set<ObvUICoreData.PersistedObvContactIdentity>) {
        
        let existingContacts = Set(selectedContacts)
        
        let contactsToAdd = contacts.subtracting(existingContacts)
        let contactsToRemove = existingContacts.subtracting(contacts)
        
        contactsToRemove.forEach({ userDidDeselect($0) })
        contactsToAdd.forEach({ userDidSelect($0) })

        store.changed.toggle()
    }

    // MARK: - SingleContactViewActionsProtocol
    
    @MainActor
    func userWantsToDeleteContact(cryptoId: ObvTypes.ObvCryptoId) async {
        
        while let contact = selectedContacts.first(where: { $0.cryptoId == cryptoId }) {
            selectedContacts.remove(contact)
            store.changed.toggle()
        }
        
        while let index = orderedContacts.firstIndex(where: { $0.cryptoId == cryptoId }) {
            orderedContacts.remove(at: index)
        }

    }

}
