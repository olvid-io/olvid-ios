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

import Foundation

/// When the app processes a received message (either from a contact or from another owned device), it uses this type to inform the engine about the appropriate processing for the attachments associated to the message.
public enum ObvAttachmentsProcessingRequest {
    
    public enum ProcessingKind {
        case deleteFromServer
        case download
    }
    
    case doNothing
    case deleteAll
    case process(processingKindForAttachmentIndex: [Int: ProcessingKind])
    
}
