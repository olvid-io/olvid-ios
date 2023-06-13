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
import MobileCoreServices
import ObvEngine

@objc(SentFyleMessageJoinWithStatus)
public final class SentFyleMessageJoinWithStatus: FyleMessageJoinWithStatus, Identifiable {
    
    public static let entityName = "SentFyleMessageJoinWithStatus"

    // MARK: Properties

    @NSManaged private var rawReceptionStatus: Int

    // MARK: Relationships
    
    @NSManaged public var sentMessage: PersistedMessageSent

    // MARK: Other variables
    
    public private(set) var status: FyleStatus {
        get {
            return FyleStatus(rawValue: self.rawStatus)!
        }
        set {
            guard newValue.rawValue != self.rawStatus else { return }
            self.rawStatus = newValue.rawValue
        }
    }

    public private(set) var receptionStatus: FyleReceptionStatus {
        get {
            return FyleReceptionStatus(rawValue: rawReceptionStatus) ?? FyleReceptionStatus.none
        }
        set {
            guard receptionStatus < newValue else { return }
            self.rawReceptionStatus = newValue.rawValue
        }
    }

    public override var message: PersistedMessage? { sentMessage }

    public override var fullFileIsAvailable: Bool { !isWiped }

    public enum FyleStatus: Int {
        case uploadable = 0
        case uploading = 1
        case complete = 2
    }

    public enum FyleReceptionStatus: Int {
        case none = 0
        case delivered = 1
        case read = 2

        static func < (lhs: Self, rhs: Self) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }
    }

    // MARK: - Getting FyleMetadata
    
    public func getFyleMetadata() -> FyleMetadata? {

        guard let fyle = self.fyle else { return nil }
        
        let uti: String
        if let _uti = ObvUTIUtils.utiOfFile(withName: self.fileName) {
            uti = _uti
        } else {
            uti = String(kUTTypeData)
        }

        return FyleMetadata(fileName: self.fileName,
                            sha256: fyle.sha256,
                            uti: uti)
        
    }
    
    public func markAsComplete() {
        tryToSetStatusTo(.complete)
    }
    

    // MARK: - Initializer
    
    convenience init?(fyleJoin: FyleJoin, persistedMessageSentObjectID: TypeSafeManagedObjectID<PersistedMessageSent>, within context: NSManagedObjectContext) {
        
        guard let fyle = fyleJoin.fyle else { return nil }

        // Pre-compute a few things

        guard let persistedMessageSent = try? PersistedMessageSent.getPersistedMessageSent(objectID: persistedMessageSentObjectID, within: context) else { return nil }

        // Call the superclass initializer

        self.init(totalByteCount: fyle.getFileSize() ?? 0,
                  fileName: fyleJoin.fileName,
                  uti: fyleJoin.uti,
                  rawStatus: FyleStatus.uploadable.rawValue,
                  messageSortIndex: persistedMessageSent.sortIndex,
                  index: fyleJoin.index,
                  fyle: fyle,
                  forEntityName: SentFyleMessageJoinWithStatus.entityName,
                  within: context)
        
        // Set the remaining properties and relationships

        self.sentMessage = persistedMessageSent
        
    }
    

    public func fyleElementOfSentJoin() -> FyleElement? {
        try? FyleElementForFyleMessageJoinWithStatus.init(self)
    }


    public override func wipe() throws {
        try super.wipe()
        tryToSetStatusTo(.complete)
    }
    
    
    func tryToSetStatusTo(_ newStatus: FyleStatus) {
        guard self.status != .complete else { return }
        self.rawStatus = newStatus.rawValue
        if self.status == .complete {
            let joinObjectID = (self as FyleMessageJoinWithStatus).typedObjectID
            Task {
                await FyleMessageJoinWithStatus.removeProgressForJoinWithObjectID(joinObjectID)
            }
        }
    }
    
    
    func tryToSetReceptionStatusTo(_ newReceptionStatus: FyleReceptionStatus) {
        guard newReceptionStatus.rawValue > receptionStatus.rawValue else { return }
        self.receptionStatus = newReceptionStatus
    }
    
}


// MARK: - Determining actions availability

extension SentFyleMessageJoinWithStatus {
    
    var copyActionCanBeMadeAvailableForSentJoin: Bool {
        return shareActionCanBeMadeAvailableForSentJoin
    }
    
    var shareActionCanBeMadeAvailableForSentJoin: Bool {
        return sentMessage.shareActionCanBeMadeAvailableForSentMessage
    }
    
    var forwardActionCanBeMadeAvailableForSentJoin: Bool {
        return shareActionCanBeMadeAvailableForSentJoin
    }

}


// MARK: - Convenience DB getters

extension SentFyleMessageJoinWithStatus {
    
    struct Predicate {
        enum Key: String {
            case sentMessage = "sentMessage"
        }
        static var isIncomplete: NSPredicate {
            NSPredicate(FyleMessageJoinWithStatus.Predicate.Key.rawStatus, DistinctFromInt: FyleStatus.complete.rawValue)
        }
        static var withoutSentMessage: NSPredicate {
            NSPredicate(withNilValueForKey: Key.sentMessage)
        }
    }

    @nonobjc static func fetchRequest() -> NSFetchRequest<SentFyleMessageJoinWithStatus> {
        return NSFetchRequest<SentFyleMessageJoinWithStatus>(entityName: SentFyleMessageJoinWithStatus.entityName)
    }

    static func getSentFyleMessageJoinWithStatus(objectID: NSManagedObjectID, within context: NSManagedObjectContext) -> SentFyleMessageJoinWithStatus? {
        let sentFyleMessageJoinWithStatus: SentFyleMessageJoinWithStatus
        do {
            guard let res = try context.existingObject(with: objectID) as? SentFyleMessageJoinWithStatus else { throw Self.makeError(message: "Could not find SentFyleMessageJoinWithStatus") }
            sentFyleMessageJoinWithStatus = res
        } catch {
            return nil
        }
        return sentFyleMessageJoinWithStatus
    }
    
    
    public static func deleteAllOrphaned(within context: NSManagedObjectContext) throws {
        let request: NSFetchRequest<NSFetchRequestResult> = SentFyleMessageJoinWithStatus.fetchRequest()
        request.predicate = Predicate.withoutSentMessage
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: request)
        try context.execute(deleteRequest)
    }
}
