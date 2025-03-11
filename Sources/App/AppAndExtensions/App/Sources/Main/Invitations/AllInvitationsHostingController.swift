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

import UIKit
import SwiftUI
import ObvTypes
import ObvUICoreData


protocol AllInvitationsHostingControllerDelegate: AnyObject {
    func userWantsToRespondToDialog(controller: AllInvitationsHostingController, obvDialog: ObvDialog) async throws
    func userWantsToAbortProtocol(controller: AllInvitationsHostingController, obvDialog: ObvTypes.ObvDialog) async throws
    func userWantsToDeleteDialog(controller: AllInvitationsHostingController, obvDialog: ObvTypes.ObvDialog) async throws
    func userWantsToDiscussWithContact(controller: AllInvitationsHostingController, ownedCryptoId: ObvCryptoId, contactCryptoId: ObvCryptoId) async throws
}


final class AllInvitationsHostingController: UIHostingController<AllInvitationsView<PersistedObvOwnedIdentity>>, AllInvitationsViewActionsProtocol {
    
    private weak var delegate: AllInvitationsHostingControllerDelegate?
    
    init(ownedIdentity: PersistedObvOwnedIdentity, delegate: AllInvitationsHostingControllerDelegate) {
        let actions = AllInvitationsViewActions()
        let view = AllInvitationsView<PersistedObvOwnedIdentity>(actions: actions, model: ownedIdentity)
        super.init(rootView: view)
        self.delegate = delegate
        actions.delegate = self
    }
    
    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // AllInvitationsViewActionsProtocol
    
    func userWantsToRespondToDialog(_ obvDialog: ObvDialog) async throws {
        try await delegate?.userWantsToRespondToDialog(controller: self, obvDialog: obvDialog)
    }
    
    func userWantsToAbortProtocol(associatedTo obvDialog: ObvTypes.ObvDialog) async throws {
        try await delegate?.userWantsToAbortProtocol(controller: self, obvDialog: obvDialog)
    }
    
    func userWantsToDeleteDialog(_ obvDialog: ObvDialog) async throws {
        try await delegate?.userWantsToDeleteDialog(controller: self, obvDialog: obvDialog)
    }
    
    func userWantsToDiscussWithContact(ownedCryptoId: ObvCryptoId, contactCryptoId: ObvCryptoId) async throws {
        try await delegate?.userWantsToDiscussWithContact(controller: self, ownedCryptoId: ownedCryptoId, contactCryptoId: contactCryptoId)
    }
}


private final class AllInvitationsViewActions: AllInvitationsViewActionsProtocol {
        
    weak var delegate: AllInvitationsViewActionsProtocol?
    
    func userWantsToRespondToDialog(_ obvDialog: ObvDialog) async throws {
        try await delegate?.userWantsToRespondToDialog(obvDialog)
    }
    
    func userWantsToAbortProtocol(associatedTo obvDialog: ObvTypes.ObvDialog) async throws {
        try await delegate?.userWantsToAbortProtocol(associatedTo: obvDialog)
    }

    func userWantsToDeleteDialog(_ obvDialog: ObvDialog) async throws {
        try await delegate?.userWantsToDeleteDialog(obvDialog)
    }
    
    func userWantsToDiscussWithContact(ownedCryptoId: ObvCryptoId, contactCryptoId: ObvCryptoId) async throws {
        try await delegate?.userWantsToDiscussWithContact(ownedCryptoId: ownedCryptoId, contactCryptoId: contactCryptoId)
    }
}
