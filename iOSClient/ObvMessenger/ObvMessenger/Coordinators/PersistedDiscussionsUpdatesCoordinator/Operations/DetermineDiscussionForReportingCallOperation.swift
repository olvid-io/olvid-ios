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
import OlvidUtils
import os.log
import ObvUICoreData


final class DetermineDiscussionForReportingCallOperation: ContextualOperationWithSpecificReasonForCancel<DetermineDiscussionForReportingCallOperationReasonForCancel>, OperationProvidingPersistedDiscussion {
    
    private let persistedCallLogItemObjectID: TypeSafeManagedObjectID<PersistedCallLogItem>
    
    var persistedDiscussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>?
    
    init(persistedCallLogItemObjectID: TypeSafeManagedObjectID<PersistedCallLogItem>) {
        self.persistedCallLogItemObjectID = persistedCallLogItemObjectID
        super.init()
    }
    
    override func main() {
        
        guard let obvContext = self.obvContext else {
            return cancel(withReason: .contextIsNil)
        }
        
        obvContext.performAndWait {
            
            do {
                
                guard let item = try PersistedCallLogItem.get(objectID: persistedCallLogItemObjectID, within: obvContext.context) else {
                    return cancel(withReason: .cannotFindPersistedCallLogItem)
                }
                
                if let groupId = try item.getGroupIdentifier() {
                    switch groupId {
                    case .groupV1(let objectID):
                        guard let contactGroup = try PersistedContactGroup.get(objectID: objectID.objectID, within: obvContext.context) else {
                            return cancel(withReason: .cannotFindPersistedContactGroup)
                        }
                        persistedDiscussionObjectID = contactGroup.discussion.typedObjectID.downcast
                        return
                    case .groupV2(let objectID):
                        guard let group = try PersistedGroupV2.get(objectID: objectID, within: obvContext.context) else {
                            return cancel(withReason: .cannotFindPersistedGroupV2)
                        }
                        guard let discussion = group.discussion else {
                            return cancel(withReason: .cannotFindPersistedGroupV2Discussion)
                        }
                        persistedDiscussionObjectID = discussion.typedObjectID.downcast
                        return
                    }
                } else {
                    if item.isIncoming {
                        guard let caller = item.logContacts.first(where: {$0.isCaller}),
                              let callerIdentity = caller.contactIdentity else {
                            return cancel(withReason: .cannotFindCaller)
                        }
                        if let oneToOneDiscussion = callerIdentity.oneToOneDiscussion {
                            persistedDiscussionObjectID = oneToOneDiscussion.typedObjectID.downcast
                            return
                        } else {
                            // Do not report this call.
                            return
                        }
                    } else if item.logContacts.count == 1,
                              let contact = item.logContacts.first,
                              let contactIdentity = contact.contactIdentity,
                              let oneToOneDiscussion = contactIdentity.oneToOneDiscussion {
                        persistedDiscussionObjectID = oneToOneDiscussion.typedObjectID.downcast
                    } else {
                        // Do not report this call.
                        return
                    }
                    
                }
                
            } catch {
                return cancel(withReason: .coreDataError(error: error))
            }
            
        }
        
    }
    
}


enum DetermineDiscussionForReportingCallOperationReasonForCancel: LocalizedErrorWithLogType {
    case coreDataError(error: Error)
    case contextIsNil
    case cannotFindPersistedCallLogItem
    case cannotFindPersistedContactGroup
    case cannotFindPersistedGroupV2
    case cannotFindPersistedGroupV2Discussion
    case cannotFindCaller
    
    var logType: OSLogType { .fault }
    
    var errorDescription: String? {
        switch self {
        case .coreDataError(error: let error):
            return "Core Data error: \(error.localizedDescription)"
        case .contextIsNil:
            return "The context is not set"
        case .cannotFindPersistedCallLogItem:
            return "Could not find PersistedCallLogItem"
        case .cannotFindPersistedContactGroup:
            return "Could not find PersistedContactGroup"
        case .cannotFindPersistedGroupV2:
            return "Could not find PersistedGroupV2"
        case .cannotFindPersistedGroupV2Discussion:
            return "Could not find PersistedGroupV2Discussion"
        case .cannotFindCaller:
            return "Could not find caller for incoming call"
        }
    }
    
}
