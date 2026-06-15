/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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
import ObvAppTypes
import ObvTypes


extension MessageReferenceJSON {
    
    public func getMessageId(ownedCryptoId: ObvCryptoId) -> MessageIdentifier {
        let authorIdentifier = MessageIdentifierInDiscussion(
            senderSequenceNumber: senderSequenceNumber,
            senderThreadIdentifier: senderThreadIdentifier,
            senderIdentifier: senderIdentifier)
        if senderIdentifier == ownedCryptoId.getIdentity() {
            return .sent(id: .authorIdentifier(writerIdentifier: authorIdentifier))
        } else {
            return .received(id: .authorIdentifier(writerIdentifier: authorIdentifier))
        }
    }
    
}
