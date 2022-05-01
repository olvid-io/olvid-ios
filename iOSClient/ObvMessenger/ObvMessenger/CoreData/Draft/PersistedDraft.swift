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

@objc(PersistedDraft)
final class PersistedDraft: NSManagedObject, Draft {
    
    private static let entityName = "PersistedDraft"
    private static let sendRequestedKey = "sendRequested"
    private static let discussionKey = "discussion"
    private static func makeError(message: String) -> Error { NSError(domain: "PersistedDraft", code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }

    // MARK: - Attributes
    
    @NSManaged private(set) var body: String?
    @NSManaged private(set) var sendRequested: Bool
    @NSManaged private var rawExistenceDuration: NSNumber?
    @NSManaged private var rawVisibilityDuration: NSNumber?
    @NSManaged private(set) var readOnce: Bool

    // MARK: - Relationships
    
    @NSManaged private(set) var discussion: PersistedDiscussion
    @NSManaged var replyTo: PersistedMessage?
    @NSManaged private(set) var unsortedDraftFyleJoins: Set<PersistedDraftFyleJoin>
    
    // MARK: - Computed Properties
    
    var fyleJoins: [FyleJoin] {
        unsortedDraftFyleJoins.sorted(by: { $0.index < $1.index })
    }

    // MARK: - Other variables
    
    private var changedKeys = Set<String>()
    
    var existenceDuration: TimeInterval? {
        get {
            guard let seconds = rawExistenceDuration?.intValue else { return nil }
            return TimeInterval(seconds)
        }
        set {
            self.rawExistenceDuration = (newValue == nil ? nil : NSNumber(value: newValue!) )
        }
    }

    var visibilityDuration: TimeInterval? {
        get {
            guard let seconds = rawVisibilityDuration?.intValue else { return nil }
            return TimeInterval(seconds)
        }
        set {
            self.rawVisibilityDuration = (newValue == nil ? nil : NSNumber(value: newValue!) )
        }
    }

    
    var isNotEmpty: Bool {
        let bodyIsNotEmpty = (body != nil && !body!.isEmpty)
        let joinsNotEmpty = !unsortedDraftFyleJoins.isEmpty
        return bodyIsNotEmpty || joinsNotEmpty
    }
    
}


// MARK: - Initializer

extension PersistedDraft {
    
    convenience init(within discussion: PersistedDiscussion) throws {
        guard let context = discussion.managedObjectContext else {
            throw Self.makeError(message: "Could not find context")
        }
        let entityDescription = NSEntityDescription.entity(forEntityName: PersistedDraft.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        self.body = nil
        self.sendRequested = false
        self.discussion = discussion
        self.replyTo = nil
        self.unsortedDraftFyleJoins = Set<PersistedDraftFyleJoin>()
        self.readOnce = false
        self.visibilityDuration = nil
        self.existenceDuration = nil
    }
    
}


// MARK: - Linking Fyle to the draft

extension PersistedDraft {

    func removeDraftFyleJoin(_ draftFyleJoin: PersistedDraftFyleJoin) {
        assert(unsortedDraftFyleJoins.contains(draftFyleJoin))
        let fyle = draftFyleJoin.fyle
        self.unsortedDraftFyleJoins.remove(draftFyleJoin)
        fyle?.remove(draftFyleJoin)
        self.managedObjectContext?.delete(draftFyleJoin)
    }
    
    
    func removeAllDraftFyleJoin() {
        unsortedDraftFyleJoins.forEach { removeDraftFyleJoin($0) }
    }
    
}


// MARK: - Other methods

extension PersistedDraft {
    
    func reset() {
        self.body = nil
        self.replyTo = nil
        if self.sendRequested {
            self.sendRequested = false
            self.changedKeys.insert(PersistedDraft.sendRequestedKey)
        }
        resetExpiration()
        removeAllDraftFyleJoin()
    }

    func resetExpiration() {
        self.readOnce = false
        self.existenceDuration = nil
        self.visibilityDuration = nil
        assert(!hasSomeExpiration)
    }
    
    func send() {
        self.sendRequested = true
        self.changedKeys.insert(PersistedDraft.sendRequestedKey)
    }
    
    func forceResend() {
        sendNewDraftToSendNotification()
    }
    
    
    func setContent(with body: String) {
        self.body = body
    }

    func appendContentToBody(_ content: String) {
        self.body?.append(content)
    }

    var hasSomeExpiration: Bool {
        readOnce == true || existenceDuration != nil || visibilityDuration != nil
    }

}

extension PersistedDraft {
    func update(with configuration: PersistedDiscussionSharedConfigurationValue?) {
        if let configuration = configuration {
            switch configuration {
            case .readOnce(readOnce: let readOnce):
                self.readOnce = readOnce
            case .existenceDuration(existenceDuration: let existenceDuration):
                self.existenceDuration = existenceDuration
            case .visibilityDuration(visibilityDuration: let visibilityDuration):
                self.visibilityDuration = visibilityDuration
            }
        } else {
            resetExpiration()
        }
    }
}


// MARK: - Convenience DB getters

extension PersistedDraft {
    
    private struct Predicate {
        static func persistedDraft(withObjectID objectID: TypeSafeManagedObjectID<PersistedDraft>) -> NSPredicate {
            NSPredicate(format: "SELF == %@", objectID.objectID)
        }
    }

    @nonobjc static func fetchRequest() -> NSFetchRequest<PersistedDraft> {
        return NSFetchRequest<PersistedDraft>(entityName: PersistedDraft.entityName)
    }
    
    static func get(objectID: TypeSafeManagedObjectID<PersistedDraft>, within context: NSManagedObjectContext) throws -> PersistedDraft? {
        let request: NSFetchRequest<PersistedDraft> = PersistedDraft.fetchRequest()
        request.predicate = Predicate.persistedDraft(withObjectID: objectID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    static func getAllUnsent(within context: NSManagedObjectContext) throws -> [PersistedDraft] {
        let request: NSFetchRequest<PersistedDraft> = PersistedDraft.fetchRequest()
        request.predicate = NSPredicate(format: "%K == YES", sendRequestedKey)
        let unsentDrafts = try context.fetch(request)
        return unsentDrafts
    }
    
    static func get(from discussion: PersistedDiscussion, within context: NSManagedObjectContext) throws -> PersistedDraft? {
        let request: NSFetchRequest<PersistedDraft> = PersistedDraft.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@", discussionKey, discussion)
        request.fetchBatchSize = 1
        return try context.fetch(request).first
    }
    
}


// Reacting to changes

extension PersistedDraft {
    
    // MARK: - Deleting Fyle when deleting the last ReceivedFyleMessageJoinWithStatus
    
    override func didSave() {
        super.didSave()
        
        if changedKeys.contains(PersistedDraft.sendRequestedKey) {
            if sendRequested {
                sendNewDraftToSendNotification()
            } else {
                let notification = ObvMessengerCoreDataNotification.draftWasSent(persistedDraftObjectID: typedObjectID)
                notification.postOnDispatchQueue()
            }
        }
    }
    
    private func sendNewDraftToSendNotification() {
        ObvMessengerCoreDataNotification.newDraftToSend(persistedDraftObjectID: typedObjectID)
            .postOnDispatchQueue()
    }
    
}
