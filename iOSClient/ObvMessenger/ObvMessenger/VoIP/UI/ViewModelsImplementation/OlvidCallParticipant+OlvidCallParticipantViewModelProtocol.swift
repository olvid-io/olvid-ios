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

import Foundation
import SwiftUI
import ObvTypes
import UI_ObvCircledInitials
import ObvUICoreData


// MARK: - Implementing OlvidCallParticipantViewModelProtocol (for the UI)

extension OlvidCallParticipant: OlvidCallParticipantViewModelProtocol {
    
    var stateLocalizedDescription: String {
        return self.state.localizedString
    }
    
    var circledInitialsConfiguration: UI_ObvCircledInitials.CircledInitialsConfiguration {
        assert(Thread.isMainThread)
        do {
            switch self.knownOrUnknown {
            case .known(contactObjectID: let contactObjectID):
                guard let persistedContact = try PersistedObvContactIdentity.get(objectID: contactObjectID.objectID, within: ObvStack.shared.viewContext) else {
                    assertionFailure()
                    return defaultCircledInitialsConfiguration
                }
                return persistedContact.circledInitialsConfiguration
            case .unknown:
                // This happens if we are a callee and do not have this participant among our contacts
                return defaultCircledInitialsConfiguration
            }
        } catch {
            assertionFailure()
            return defaultCircledInitialsConfiguration
        }
    }
    
    
    private var defaultCircledInitialsConfiguration: UI_ObvCircledInitials.CircledInitialsConfiguration {
        if let firstCharacter = self.displayName.trimmingWhitespacesAndNewlines().first {
            return .contact(initial: String(firstCharacter),
                            photo: nil,
                            showGreenShield: false,
                            showRedShield: false,
                            cryptoId: self.cryptoId,
                            tintAdjustementMode: .normal)
        } else {
            return .icon(.person)
        }
    }
     
}
