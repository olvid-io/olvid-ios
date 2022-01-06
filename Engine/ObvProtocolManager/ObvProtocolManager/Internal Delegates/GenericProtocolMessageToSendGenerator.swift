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
import ObvCrypto
import ObvMetaManager

protocol GenericProtocolMessageToSendGenerator: ObvChannelProtocolMessageToSendGenerator {
    
    func generateGenericProtocolMessageToSend() -> GenericProtocolMessageToSend?
    func generateObvChannelDialogMessageToSend() -> ObvChannelDialogMessageToSend?
    
}

// A GenericProtocolMessageToSendGenerator is automagically a ObvChannelProtocolMessageToSendGenerator. This is used for concrete protocol message, which only have to implement `GenericProtocolMessageToSendGenerator`
extension GenericProtocolMessageToSendGenerator {
    
    func generateObvChannelProtocolMessageToSend(with prng: PRNGService) -> ObvChannelProtocolMessageToSend? {
        let genericProtocolMessageToSend = self.generateGenericProtocolMessageToSend()
        return genericProtocolMessageToSend?.generateObvChannelProtocolMessageToSend(with: prng)
    }
    
    func generateObvChannelDialogMessageToSend() -> ObvChannelDialogMessageToSend? {
        let genericProtocolMessageToSend = self.generateGenericProtocolMessageToSend()
        return genericProtocolMessageToSend?.generateObvChannelDialogMessageToSend()
    }
    
    func generateObvChannelServerQueryMessageToSend(serverQueryType: ObvChannelServerQueryMessageToSend.QueryType) -> ObvChannelServerQueryMessageToSend? {
        let genericProtocolMessageToSend = self.generateGenericProtocolMessageToSend()
        return genericProtocolMessageToSend?.generateObvChannelServerQueryMessageToSend(serverQueryType: serverQueryType)
    }
}
