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
import OlvidUtils


@objc(FyleMessageJoinWithStatus)
class FyleMessageJoinWithStatus: NSManagedObject, ObvErrorMaker, FyleJoin {
    
    // MARK: - Internal constants

    private static let entityName = "FyleMessageJoinWithStatus"
    static let errorDomain = "FyleMessageJoinWithStatus"

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
    @NSManaged private(set) var totalByteCount: Int64 // Was totalUnitCount
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
    
    // MARK: - Initializer

    convenience init(totalByteCount: Int64, fileName: String, uti: String, rawStatus: Int, messageSortIndex: Double, index: Int, fyle: Fyle, forEntityName entityName: String, within context: NSManagedObjectContext) {

        let entityDescription = NSEntityDescription.entity(forEntityName: entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)

        self.index = index
        self.fileName = fileName
        self.uti = uti
        self.rawStatus = rawStatus
        self.messageSortIndex = messageSortIndex
        self.isWiped = false
        self.totalByteCount = totalByteCount
        
        self.fyle = fyle
    }


    func wipe() throws {
        self.isWiped = true
        self.fyle = nil
        self.fileName = ""
        self.totalByteCount = 0
        self.uti = ""
    }


    // MARK: - Managing a progress object in the view context
    
    @MainActor
    static func setProgressTo(_ newProgress: Float, forJoinWithObjectID joinObjectID: TypeSafeManagedObjectID<FyleMessageJoinWithStatus>) {
        if let progressObject = progressForJoinWithObjectID[joinObjectID] {
            let newCompletedUnitCount = Int64(Double(newProgress) * Double(progressObject.totalUnitCount))
            guard newCompletedUnitCount > progressObject.completedUnitCount else { return }
            progressObject.completedUnitCount = newCompletedUnitCount
        } else {
            guard let joinObject = try? FyleMessageJoinWithStatus.get(objectID: joinObjectID.objectID, within: ObvStack.shared.viewContext) else { return }
            let progressObject = Progress(totalUnitCount: joinObject.totalByteCount)
            let newCompletedUnitCount = Int64(Double(newProgress) * Double(progressObject.totalUnitCount))
            progressObject.completedUnitCount = newCompletedUnitCount
            progressForJoinWithObjectID[joinObjectID] = progressObject
        }
    }


    private static var progressForJoinWithObjectID = [TypeSafeManagedObjectID<FyleMessageJoinWithStatus>: Progress]()


    @MainActor
    var progressObject: Progress {
        assert(self.managedObjectContext?.concurrencyType == .mainQueueConcurrencyType)
        if let progress = FyleMessageJoinWithStatus.progressForJoinWithObjectID[self.typedObjectID] {
            return progress
        } else {
            let progress = Progress(totalUnitCount: self.totalByteCount)
            FyleMessageJoinWithStatus.progressForJoinWithObjectID[self.typedObjectID] = progress
            return progress
        }
    }
    

    @MainActor
    static func removeProgressForJoinWithObjectID(_ joinObjectID: TypeSafeManagedObjectID<FyleMessageJoinWithStatus>) {
        _ = progressForJoinWithObjectID.removeValue(forKey: joinObjectID)
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
