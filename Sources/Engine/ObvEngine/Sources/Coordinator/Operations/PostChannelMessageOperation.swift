/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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
import CoreData
import OlvidUtils
import ObvMetaManager
import ObvCrypto


final class PostChannelMessageOperation: ContextualOperationWithSpecificReasonForCancel<CoreDataOperationReasonForCancel>, @unchecked Sendable {
    
    private let message: ObvChannelProtocolMessageToSend
    private let prng: any PRNGService
    private let channelDelegate: any ObvChannelDelegate
    
    init(message: ObvChannelProtocolMessageToSend, prng: any PRNGService, channelDelegate: any ObvChannelDelegate) {
        self.message = message
        self.channelDelegate = channelDelegate
        self.prng = prng
        super.init()
    }
    
    override func main(obvContext: ObvContext, viewContext: NSManagedObjectContext) {
        do {
            _ = try channelDelegate.postChannelMessage(message, randomizedWith: prng, within: obvContext)
        } catch {
            return cancel(withReason: .coreDataError(error: error))
        }
    }
    
}
