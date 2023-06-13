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
import CoreData
import os.log
import ObvEngine
import ObvTypes
import OlvidUtils
import ObvUICoreData


final class MarkAsOpenedOperation: ContextualOperationWithSpecificReasonForCancel<MarkAsOpenedOperationReasonForCancel> {

    let receivedFyleMessageJoinWithStatusID: TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>

    init(receivedFyleMessageJoinWithStatusID: TypeSafeManagedObjectID<ReceivedFyleMessageJoinWithStatus>) {
        self.receivedFyleMessageJoinWithStatusID = receivedFyleMessageJoinWithStatusID
        super.init()
    }

    override func main() {
        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }

        obvContext.performAndWait {
            do {
                guard let fyle = try ReceivedFyleMessageJoinWithStatus.get(objectID: receivedFyleMessageJoinWithStatusID, within: obvContext.context) else {
                    return cancel(withReason: .couldNotFindReceivedFyleMessageJoinWithStatus)
                }
                guard !fyle.receivedMessage.readingRequiresUserAction else {
                    assertionFailure()
                    return cancel(withReason: .tryToMarkAsOpenedAMessageWithReadingRequiresUserAction)
                }
                fyle.markAsOpened()
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
        }
    }

}

enum MarkAsOpenedOperationReasonForCancel: LocalizedErrorWithLogType {
    case contextIsNil
    case coreDataError(error: Error)
    case couldNotFindReceivedFyleMessageJoinWithStatus
    case tryToMarkAsOpenedAMessageWithReadingRequiresUserAction

    var logType: OSLogType { .fault }

    public var errorDescription: String? {
        switch self {
        case .contextIsNil:
            return "Context is nil"
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        case .couldNotFindReceivedFyleMessageJoinWithStatus:
            return "Could not find the received fyle message join with status in database"
        case .tryToMarkAsOpenedAMessageWithReadingRequiresUserAction:
            return "Try to mark as opened a message with reading requires user action"
        }
    }

}
