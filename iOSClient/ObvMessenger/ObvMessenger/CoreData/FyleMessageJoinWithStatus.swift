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
import UIKit


@objc(FyleMessageJoinWithStatus)
class FyleMessageJoinWithStatus: NSManagedObject {
    
    // MARK: - Internal constants

    private static let entityName = "FyleMessageJoinWithStatus"

    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: FyleMessageJoinWithStatus.self))
    private static func makeError(message: String) -> Error {
        NSError(domain: String(describing: self), code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message])
    }
    private func makeError(message: String) -> Error {
        FyleMessageJoinWithStatus.makeError(message: message)
    }

    // MARK: - Properties

    @NSManaged private(set) var fileName: String
    @NSManaged private(set) var index: Int // Corresponds to the index of this attachment in the message. Used together with messageSortIndex to sort all joins received in a discussion
    @NSManaged private(set) var isWiped: Bool
    @NSManaged private(set) var messageSortIndex: Double // Equal to the message sortIndex, used to sort FyleMessageJoinWithStatus instances in the gallery
    @NSManaged internal var rawStatus: Int
    @NSManaged private(set) var totalUnitCount: Int64
    @NSManaged private(set) var uti: String

    // MARK: - Relationships

    @NSManaged private(set) var fyle: Fyle? // If nil, this entity is eventually cascade-deleted
    
    // MARK: - Other variables
    
    var message: PersistedMessage? {
        assertionFailure("Must be overriden by subclasses")
        return nil
    }

    var readOnce: Bool {
        message?.readOnce ?? false
    }
    
    var fullFileIsAvailable: Bool {
        assertionFailure("Must be overriden by subclasses")
        return false
    }

    /// Helper methods allowing to "store" a progress in an attachment loaded in the view context. This is used to in conjonction with
    /// the (new) view controller showing a single discussion, allowing e.g. the user to initiate, pause, and follow the download of an attachment.
    /// For now, this is only used for displaying progresses within the new discussion view designed for iOS14+.
    static var progressesForAttachment = [NSManagedObjectID: Progress]()
    var progress: Progress? {
        get {
            assert(Thread.isMainThread)
            return FyleMessageJoinWithStatus.progressesForAttachment[self.objectID]
        }
        set {
            assert(Thread.isMainThread)
            FyleMessageJoinWithStatus.progressesForAttachment[self.objectID] = newValue
        }
    }
    

    // MARK: - Initializer

    convenience init(totalUnitCount: Int64, fileName: String, uti: String, rawStatus: Int, messageSortIndex: Double, index: Int, fyle: Fyle, forEntityName entityName: String, within context: NSManagedObjectContext) {

        let entityDescription = NSEntityDescription.entity(forEntityName: entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)

        self.index = index
        self.fileName = fileName
        self.uti = uti
        self.rawStatus = rawStatus
        self.messageSortIndex = messageSortIndex
        self.isWiped = false
        self.totalUnitCount = totalUnitCount
        
        self.fyle = fyle
    }


    @objc func wipe() throws {
        self.isWiped = true
        self.fyle = nil
        self.fileName = ""
        self.totalUnitCount = 0
        self.uti = ""
    }

}


// MARK: - Convenience DB getters

extension FyleMessageJoinWithStatus {
    
    struct Predicate {
        enum Key: String {
            case fileName = "fileName"
            case index = "index"
            case fyle = "fyle"
            case rawStatus = "rawStatus"
            case uti = "uti"
            case messageSortIndex = "messageSortIndex"
            case isWiped = "isWiped"
        }
        static func withObjectIDs(_ objectIDs: Set<TypeSafeManagedObjectID<FyleMessageJoinWithStatus>>) -> NSPredicate {
            NSPredicate(format: "SELF IN %@", objectIDs.map({ $0.objectID }))
        }
        static func isSentFyleMessageJoinWithStatusInDiscussion(_ discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>) -> NSPredicate {
            let discussionKey = [SentFyleMessageJoinWithStatus.Predicate.Key.sentMessage.rawValue, PersistedMessage.Predicate.Key.discussion.rawValue].joined(separator: ".")
            return NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(withEntity: SentFyleMessageJoinWithStatus.entity()),
                NSPredicate(format: "%K == %@", discussionKey, discussionObjectID.objectID),
            ])
        }
        static func withUTI(_ uti: String) -> NSPredicate {
            NSPredicate(Key.uti, EqualToString: uti)
        }
        static func isWiped(is value: Bool) -> NSPredicate {
            NSPredicate(Key.isWiped, is: value)
        }
    }
    
    @nonobjc static func fetchRequest() -> NSFetchRequest<FyleMessageJoinWithStatus> {
        return NSFetchRequest<FyleMessageJoinWithStatus>(entityName: FyleMessageJoinWithStatus.entityName)
    }

    
    static func get(objectID: NSManagedObjectID, within context: NSManagedObjectContext) throws -> FyleMessageJoinWithStatus? {
        return try context.existingObject(with: objectID) as? FyleMessageJoinWithStatus
    }

    
    static func getAllWithObjectIDs(_ objectIDs: Set<TypeSafeManagedObjectID<FyleMessageJoinWithStatus>>, within context: NSManagedObjectContext) throws -> Set<FyleMessageJoinWithStatus> {
        let request: NSFetchRequest<FyleMessageJoinWithStatus> = FyleMessageJoinWithStatus.fetchRequest()
        request.predicate = Predicate.withObjectIDs(objectIDs)
        return Set(try context.fetch(request))
    }
        
}


// MARK: - On save

extension FyleMessageJoinWithStatus {
    
    override func didSave() {
        super.didSave()
        
        assert(!Thread.isMainThread)

        // When we save an "attachment", we reload the message within the view context
        if let messageObjectID = message?.objectID {
            DispatchQueue.main.async {
                if let message = ObvStack.shared.viewContext.registeredObject(for: messageObjectID) {
                    ObvStack.shared.viewContext.refresh(message, mergeChanges: true)
                }
            }
        }
        
    }
    
}
