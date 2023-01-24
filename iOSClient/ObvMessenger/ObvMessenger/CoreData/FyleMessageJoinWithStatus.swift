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
    
    // MARK: - Transient properties (allowing to feed SwiftUI progress views)
    
    @NSManaged private(set) var fractionCompleted: Double
    @NSManaged private(set) var estimatedTimeRemaining: TimeInterval
    @NSManaged private(set) var throughput: Int

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
    
    /// This method updates the progress object corresponding to the `FyleMessageJoinWithStatus` referenced by the objectID by updating its completed unit count.
    /// It also updates the transiant properties of the object, as these attributes are observed by the SwiftUI allowing to track the progress of the download/upload.
    @MainActor
    static func setProgressTo(_ newProgress: Float, forJoinWithObjectID joinObjectID: TypeSafeManagedObjectID<FyleMessageJoinWithStatus>) {
        assert(Thread.isMainThread)
        guard let joinObject = try? FyleMessageJoinWithStatus.get(objectID: joinObjectID.objectID, within: ObvStack.shared.viewContext) else { return }
        let progressObject = joinObject.progressObject
        let newCompletedUnitCount = Int64(Double(newProgress) * Double(progressObject.totalUnitCount))
        guard newCompletedUnitCount > progressObject.completedUnitCount else { return }
        progressObject.completedUnitCount = newCompletedUnitCount
        // The following uses the progress we just updated to update the transient variables of the join object observed by SwiftUI views
        updateTransientProgressAttributes(of: joinObject, using: progressObject)
    }
    
    
    @MainActor
    private static func updateTransientProgressAttributes(of joinObject: FyleMessageJoinWithStatus, using progressObject: ObvProgress) {
        assert(Thread.isMainThread)
        assert(joinObject.managedObjectContext?.concurrencyType == .mainQueueConcurrencyType)
        joinObject.fractionCompleted = progressObject.fractionCompleted
        joinObject.estimatedTimeRemaining = progressObject.estimatedTimeRemaining ?? 0
        joinObject.throughput = progressObject.throughput ?? 0
    }


    private static var progressForJoinWithObjectID = [TypeSafeManagedObjectID<FyleMessageJoinWithStatus>: ObvProgress]()


    /// The progress associated with this `FyleMessageJoinWithStatus` instance.
    ///
    /// If the progress already exists in the private static `progressForJoinWithObjectID` array, it is returned. Otherwise, a new progress is created, store in the array and returned.
    /// Note that we use an `ObvProgress` subclass of `Progress`, which is a custom sublcass that implements the logic allowing to compute the current throughput and estimated time remaining.
    @MainActor
    var progressObject: ObvProgress {
        assert(Thread.isMainThread)
        assert(self.managedObjectContext?.concurrencyType == .mainQueueConcurrencyType)
        if let progress = FyleMessageJoinWithStatus.progressForJoinWithObjectID[self.typedObjectID] {
            return progress
        } else {
            let progress = ObvProgress(totalUnitCount: self.totalByteCount)
            FyleMessageJoinWithStatus.progressForJoinWithObjectID[self.typedObjectID] = progress
            return progress
        }
    }
    

    @MainActor
    static func removeProgressForJoinWithObjectID(_ joinObjectID: TypeSafeManagedObjectID<FyleMessageJoinWithStatus>) {
        assert(Thread.isMainThread)
        _ = progressForJoinWithObjectID.removeValue(forKey: joinObjectID)
    }
    
    
    /// As the progresses are only refreshed when their completed unit count is incremented, we implement this method to implement a way to force a refresh of all the progresses.
    /// This is used, in particular, when the download/upload of an attachment is stalled. In that case, we use this method to update the `ObvProgress` of the attachment, allowing to reflect the decrease of the throughput and the increase of the estimated remaining time.
    @MainActor
    static func refreshAllProgresses() async {
        for (joinObjectID, progressObject) in progressForJoinWithObjectID {
            guard let joinObject = ObvStack.shared.viewContext.registeredObjects.first(where: { $0.objectID == joinObjectID.objectID }) as? FyleMessageJoinWithStatus else { continue }
            await progressObject.refreshThroughputAndEstimatedTimeRemaining()
            updateTransientProgressAttributes(of: joinObject, using: progressObject)
        }
    }
    
    
    static let formatterForEstimatedTimeRemaining: DateComponentsFormatter = {
        let dcf = DateComponentsFormatter()
        dcf.unitsStyle = .short
        dcf.includesApproximationPhrase = true
        dcf.includesTimeRemainingPhrase = true
        dcf.allowedUnits = [.day, .hour, .minute, .second]
        return dcf
    }()

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
