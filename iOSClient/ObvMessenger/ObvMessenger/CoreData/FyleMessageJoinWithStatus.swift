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

@objc(FyleMessageJoinWithStatus)
class FyleMessageJoinWithStatus: NSManagedObject {
    
    // MARK: - Internal constants

    private static let entityName = "FyleMessageJoinWithStatus"
    private static let fyleKey = "fyle"
    internal static let rawStatusKey = "rawStatus"

    private let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: self))
    private static func makeError(message: String) -> Error {
        NSError(domain: String(describing: self), code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message])
    }
    private func makeError(message: String) -> Error {
        FyleMessageJoinWithStatus.makeError(message: message)
    }

    // MARK: - Properties

    @NSManaged private(set) var fileName: String
    @NSManaged private(set) var isWiped: Bool
    @NSManaged internal var rawStatus: Int
    @NSManaged private(set) var totalUnitCount: Int64
    @NSManaged private(set) var uti: String

    // MARK: - Relationships

    @NSManaged private(set) var fyle: Fyle? // If nil, this entity is eventually cascade-deleted
    
    // MARK: - Other variables
    
    var message: PersistedMessage? {
        if let join = self as? SentFyleMessageJoinWithStatus {
            return join.sentMessage
        } else if let join = self as? ReceivedFyleMessageJoinWithStatus {
            return join.receivedMessage
        } else {
            assertionFailure()
            return nil
        }
    }

    var readOnce: Bool {
        message?.readOnce ?? false
    }
    
    var fullFileIsAvailable: Bool {
        if let received = self as? ReceivedFyleMessageJoinWithStatus {
            return received.status == .complete
        } else if self is SentFyleMessageJoinWithStatus {
            return true
        } else {
            assertionFailure("Unknown FyleMessageJoinWithStatus subclass")
            return false
        }
    }

    var fyleElement: FyleElement? {
        try? FyleElementForFyleMessageJoinWithStatus(self)
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
    
}


// MARK: - Initializer

extension FyleMessageJoinWithStatus {
    
    convenience init(totalUnitCount: Int64, fileName: String, uti: String, rawStatus: Int, fyle: Fyle, forEntityName entityName: String, within context: NSManagedObjectContext) {

        let entityDescription = NSEntityDescription.entity(forEntityName: entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)

        self.fileName = fileName
        self.uti = uti
        self.rawStatus = rawStatus
        self.isWiped = false
        self.totalUnitCount = totalUnitCount
        
        self.fyle = fyle
    }


    func wipe() {
        self.isWiped = true
        self.fyle = nil
    }

}


// MARK: - Convenience DB getters

extension FyleMessageJoinWithStatus {
    
    private struct Predicate {
        static func withObjectIDs(_ objectIDs: Set<TypeSafeManagedObjectID<FyleMessageJoinWithStatus>>) -> NSPredicate {
            NSPredicate(format: "SELF IN %@", objectIDs.map({ $0.objectID }))
        }
    }
    
    @nonobjc static func fetchRequest() -> NSFetchRequest<FyleMessageJoinWithStatus> {
        return NSFetchRequest<FyleMessageJoinWithStatus>(entityName: FyleMessageJoinWithStatus.entityName)
    }

    
    static func get(objectID: NSManagedObjectID, within context: NSManagedObjectContext) -> FyleMessageJoinWithStatus? {
        let fyleMessageJoinWithStatus: FyleMessageJoinWithStatus
        do {
            guard let res = try context.existingObject(with: objectID) as? FyleMessageJoinWithStatus else { throw NSError() }
            fyleMessageJoinWithStatus = res
        } catch {
            return nil
        }
        return fyleMessageJoinWithStatus
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
