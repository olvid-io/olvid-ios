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

import Foundation
import Intents
import ObvEngine

final class ProcessINStartCallIntentOperation: Operation {
    
    let startCallIntent: INStartCallIntent
    let obvEngine: ObvEngine
    
    init(startCallIntent: INStartCallIntent, obvEngine: ObvEngine) {
        self.startCallIntent = startCallIntent
        self.obvEngine = obvEngine
        super.init()
    }
    
    override func main() {
        guard let handle = startCallIntent.contacts?.first?.personHandle?.value else { return cancel() }

        ObvStack.shared.performBackgroundTaskAndWait { (context) in

            if let callUUID = UUID(handle),
               let item = try? PersistedCallLogItem.get(callUUID: callUUID, within: context) {
                let contacts = item.logContacts.compactMap { $0.contactIdentity?.typedObjectID }
                ObvMessengerInternalNotification.userWantsToCallButWeShouldCheckSheIsAllowedTo(contactIDs: contacts, groupId: try? item.getGroupId()).postOnDispatchQueue()
            } else {
                // Let be compatible with previous 1to1 versions
                if let contact = try? PersistedObvContactIdentity.getAll(within: context).first(where: { $0.getGenericHandleValue(engine: obvEngine) == handle}) {
                    let contacts = [contact.typedObjectID]
                    ObvMessengerInternalNotification.userWantsToCallButWeShouldCheckSheIsAllowedTo(contactIDs: contacts, groupId: nil).postOnDispatchQueue()
                }
            }
        }
        
    }
    
}

fileprivate extension PersistedObvContactIdentity {

    func getGenericHandleValue(engine: ObvEngine) -> String? {
        guard let context = self.managedObjectContext else { assertionFailure(); return nil }
        var _handleTagData: Data?
        context.performAndWait {
            guard let ownedIdentity = self.ownedIdentity else { assertionFailure(); return }
            do {
                _handleTagData = try engine.computeTagForOwnedIdentity(with: ownedIdentity.cryptoId, on: self.cryptoId.getIdentity())
            } catch {
                assertionFailure()
                return
            }
        }
        guard let handleTagData = _handleTagData else { assertionFailure(); return nil }
        return handleTagData.base64EncodedString()
    }

}
