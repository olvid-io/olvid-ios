/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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
import OlvidUtils
import ObvSettings
import ObvTypes
import ObvAppTypes
import ObvUserNotificationsSounds


@objc(PersistedDiscussionLocalConfiguration)
public final class PersistedDiscussionLocalConfiguration: NSManagedObject {
    
    private static let entityName = "PersistedDiscussionLocalConfiguration"
    private static let logger = Logger(subsystem: ObvUICoreDataConstants.logSubsystem, category: entityName)

    // MARK: Attributes

    @NSManaged public private(set) var defaultEmoji: String?
    @NSManaged public private(set) var muteNotificationsEndDate: Date?
    @NSManaged private var rawAutoRead: NSNumber?
    @NSManaged private var rawCountBasedRetention: NSNumber?
    @NSManaged private var rawCountBasedRetentionIsActive: NSNumber?
    @NSManaged private var rawDoNotifyWhenMentionnedInMutedDiscussion: NSNumber?
    @NSManaged private var rawDoSendReadReceipt: NSNumber?
    @NSManaged private var rawNotificationSound: String?
    @NSManaged private(set) var rawPerformInteractionDonation: NSNumber?
    @NSManaged private var rawRetainWipedOutboundMessages: NSNumber?
    @NSManaged private var rawTimeBasedRetention: NSNumber?

    // MARK: Relationships

    @NSManaged public private(set) var discussion: PersistedDiscussion?

    // MARK: Computed variables

    public var autoRead: Bool? {
        get {
            rawAutoRead?.boolValue
        }
        set {
            guard newValue != autoRead else { return }
            rawAutoRead = (newValue == nil ? nil : newValue! as NSNumber)
        }
    }

    /// If `nil`, we should use the app default value. Otherwise, the user did override the default value.
    public var countBasedRetentionIsActive: Bool? {
        get {
            rawCountBasedRetentionIsActive?.boolValue
        }
        set {
            guard newValue != countBasedRetentionIsActive else { return }
            rawCountBasedRetentionIsActive = (newValue == nil ? nil : newValue! as NSNumber)
            // Each time this value changes, we reset the count
            countBasedRetention = nil
        }
    }

    public var countBasedRetention: Int? {
        get {
            guard let raw = rawCountBasedRetention else { return nil }
            return raw.intValue
        }
        set {
            guard newValue != countBasedRetention else { return }
            rawCountBasedRetention = (newValue == nil ? nil : max(1, newValue!) as NSNumber)
        }
    }
    
    public var timeBasedRetention: DurationOptionAltOverride {
        get {
            guard let seconds = rawTimeBasedRetention?.intValue else { return .useAppDefault }
            return DurationOptionAltOverride(rawValue: seconds) ?? .useAppDefault
        }
        set {
            self.rawTimeBasedRetention = (newValue == .useAppDefault ? nil : NSNumber(value: newValue.rawValue) )
        }
    }

    public private(set) var doSendReadReceipt: Bool? {
        get {
            rawDoSendReadReceipt?.boolValue
        }
        set {
            guard newValue != doSendReadReceipt else { return }
            rawDoSendReadReceipt = (newValue == nil ? nil : newValue! as NSNumber)
        }
    }
    
    
    /// Returns `true` iff the value had to be changed in database
    func setDoSendReadReceipt(to newValue: Bool?) -> Bool {
        guard doSendReadReceipt != newValue else { return false }
        doSendReadReceipt = newValue
        return true
    }

    
    public var retainWipedOutboundMessages: Bool? {
        get {
            rawRetainWipedOutboundMessages?.boolValue
        }
        set {
            guard newValue != retainWipedOutboundMessages else { return }
            rawRetainWipedOutboundMessages = (newValue == nil ? nil : newValue! as NSNumber)
        }
    }

    public var notificationSound: NotificationSound? {
        get {
            guard let soundIdentifier = rawNotificationSound else { return nil }
            return NotificationSound.allCases.first { $0.identifier == soundIdentifier }
        }
        set {
            if let newValue {
                guard newValue.identifier != rawNotificationSound else { return }
                rawNotificationSound = newValue.identifier
            } else {
                rawNotificationSound = nil
            }
        }
    }

    public var performInteractionDonation: Bool? {
        get {
            rawPerformInteractionDonation?.boolValue
        }
        set {
            guard newValue != performInteractionDonation else { return }
            rawPerformInteractionDonation = (newValue == nil ? nil : newValue! as NSNumber)
        }
    }

    /// Returns the discussion's mention notification mode
    /// - SeeAlso: ``DiscussionMentionNotificationMode``
    private(set) public var mentionNotificationMode: DiscussionMentionNotificationMode {
        get {
            guard let boolValue = rawDoNotifyWhenMentionnedInMutedDiscussion?.boolValue else {
                return .globalDefault
            }
            return boolValue ? .alwaysNotifyWhenMentionned : .neverNotifyWhenDiscussionIsMuted
        }
        set {
            switch newValue {
            case .globalDefault:
                rawDoNotifyWhenMentionnedInMutedDiscussion = nil
            case .neverNotifyWhenDiscussionIsMuted:
                rawDoNotifyWhenMentionnedInMutedDiscussion = false
            case .alwaysNotifyWhenMentionned:
                rawDoNotifyWhenMentionnedInMutedDiscussion = true
            }
        }
    }

    // Other variables
    
    private var updatedLocalConfigurationValueTypes = Set<PersistedDiscussionLocalConfigurationValueType>()
    
    /// Used when restoring a sync snapshot or when restoring a backup to prevent any notification on insertion
    private var isInsertedWhileRestoringSyncSnapshot = false

    
    // MARK: - Observers
    
    private static var observersHolder = PersistedDiscussionLocalConfigurationObserversHolder()
    
    public static func addObserver(_ newObserver: PersistedDiscussionLocalConfigurationObserver) async {
        await observersHolder.addObserver(newObserver)
    }

}

private enum PersistedDiscussionLocalConfigurationValueType: CaseIterable, Hashable {
    case autoRead
    case retainWipedOutboundMessages
    case doSendReadReceipt
    case mentionNotificationMode
    case countBasedRetentionIsActive
    case countBasedRetention
    case timeBasedRetention
    case muteNotificationsEndDate
    case defaultEmoji
    case notificationSound
    case performInteractionDonation
}

public enum PersistedDiscussionLocalConfigurationValue {
    case autoRead(_ autoRead: Bool?)
    case retainWipedOutboundMessages(_ retainWipedOutboundMessages: Bool?)
    case doSendReadReceipt(_ doSendReadReceipt: Bool?)
    case mentionNotificationMode(_ mode: DiscussionMentionNotificationMode)
    case countBasedRetentionIsActive(_ countBasedRetentionIsActive: Bool?)
    case countBasedRetention(_ countBasedRetention: Int?)
    case timeBasedRetention(_ timeBasedRetention: DurationOptionAltOverride)
    case muteNotificationsEndDate(_ muteNotificationsEndDate: Date?)
    case defaultEmoji(_ emoji: String?)
    case notificationSound(_ notificationSound: NotificationSound?)
    case performInteractionDonation(_ performInteractionDonation: Bool?)
    
    fileprivate var type: PersistedDiscussionLocalConfigurationValueType {
        switch self {
        case .autoRead: return .autoRead
        case .retainWipedOutboundMessages: return .retainWipedOutboundMessages
        case .doSendReadReceipt: return .doSendReadReceipt
        case .mentionNotificationMode: return .mentionNotificationMode
        case .countBasedRetentionIsActive: return .countBasedRetentionIsActive
        case .countBasedRetention: return .countBasedRetention
        case .timeBasedRetention: return .timeBasedRetention
        case .muteNotificationsEndDate: return .muteNotificationsEndDate
        case .defaultEmoji: return .defaultEmoji
        case .notificationSound: return .notificationSound
        case .performInteractionDonation: return .performInteractionDonation
        }
    }
    
}


// MARK: Mute Notifications End Date helpers

extension PersistedDiscussionLocalConfiguration {
    
    /// Helper attribute, this is solely to be used for UI-related purposes. Like showing the moon icon on the discussions list to indicate that this discussion is muted
    var hasNotificationsMuted: Bool {
        return hasValidMuteNotificationsEndDate
    }


    var hasValidMuteNotificationsEndDate: Bool {
        guard let muteNotificationsEndDate = muteNotificationsEndDate else { return false }
        return muteNotificationsEndDate > Date()
    }


    public var currentMuteNotificationsEndDate: Date? {
        guard hasValidMuteNotificationsEndDate else { return nil }
        return muteNotificationsEndDate
    }


    public static func formatDateForMutedNotification(_ date: Date) -> String {
        let df = DateFormatter()
        df.doesRelativeDateFormatting = false
        df.dateStyle = Calendar.current.isDateInToday(date) ? .none : .medium
        df.timeStyle = .short
        return df.string(from: date)
    }

}


// MARK: Update

extension PersistedDiscussionLocalConfiguration {

    public func update(with newValue: PersistedDiscussionLocalConfigurationValue) {
        switch newValue {
        case .autoRead(autoRead: let autoRead):
            if self.autoRead != autoRead {
                self.autoRead = autoRead
                updatedLocalConfigurationValueTypes.insert(.autoRead)
            }
        case .retainWipedOutboundMessages(retainWipedOutboundMessages: let retainWipedOutboundMessages):
            if self.retainWipedOutboundMessages != retainWipedOutboundMessages {
                self.retainWipedOutboundMessages = retainWipedOutboundMessages
                updatedLocalConfigurationValueTypes.insert(.retainWipedOutboundMessages)
            }
        case .mentionNotificationMode(mode: let mode):
	    if self.mentionNotificationMode != mode {
                self.mentionNotificationMode = mode
	    }
        case .doSendReadReceipt(doSendReadReceipt: let doSendReadReceipt):
            if self.doSendReadReceipt != doSendReadReceipt {
                self.doSendReadReceipt = doSendReadReceipt
                updatedLocalConfigurationValueTypes.insert(.doSendReadReceipt)
            }
        case .countBasedRetentionIsActive(countBasedRetentionIsActive: let countBasedRetentionIsActive):
            if self.countBasedRetentionIsActive != countBasedRetentionIsActive {
                self.countBasedRetentionIsActive = countBasedRetentionIsActive
                updatedLocalConfigurationValueTypes.insert(.countBasedRetentionIsActive)
            }
        case .countBasedRetention(countBasedRetention: let countBasedRetention):
            if self.countBasedRetention != countBasedRetention {
                self.countBasedRetention = countBasedRetention
                updatedLocalConfigurationValueTypes.insert(.countBasedRetention)
            }
        case .timeBasedRetention(timeBasedRetention: let timeBasedRetention):
            if self.timeBasedRetention != timeBasedRetention {
                self.timeBasedRetention = timeBasedRetention
                updatedLocalConfigurationValueTypes.insert(.timeBasedRetention)
            }
        case .muteNotificationsEndDate(let newMuteNotificationsEndDate):
            if self.muteNotificationsEndDate != newMuteNotificationsEndDate {
                self.muteNotificationsEndDate = newMuteNotificationsEndDate
                updatedLocalConfigurationValueTypes.insert(.muteNotificationsEndDate)
                try? discussion?.refreshNumberOfNewMessages()
            }
        case .defaultEmoji(emoji: let emoji):
            if self.defaultEmoji != emoji {
                self.defaultEmoji = emoji
                updatedLocalConfigurationValueTypes.insert(.defaultEmoji)
            }
        case .notificationSound(let notificationSound):
            if self.notificationSound != notificationSound {
                self.notificationSound = notificationSound
                updatedLocalConfigurationValueTypes.insert(.notificationSound)
            }
        case .performInteractionDonation(let performInteractionDonation):
            if self.performInteractionDonation != performInteractionDonation {
                self.performInteractionDonation = performInteractionDonation
                updatedLocalConfigurationValueTypes.insert(.performInteractionDonation)
            }
        }
    }

}

// MARK: - Initializer

extension PersistedDiscussionLocalConfiguration {
    
    convenience init(discussion: PersistedDiscussion, isRestoringSyncSnapshotOrBackup: Bool) throws {
        guard let context = discussion.managedObjectContext else { assertionFailure(); throw ObvUICoreDataError.noContext }
        let entityDescription = NSEntityDescription.entity(forEntityName: PersistedDiscussionLocalConfiguration.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        self.isInsertedWhileRestoringSyncSnapshot = isRestoringSyncSnapshotOrBackup
        self.discussion = discussion
        self.rawAutoRead = nil
        self.countBasedRetentionIsActive = nil
        self.countBasedRetention = nil
        self.timeBasedRetention = .useAppDefault
        self.rawRetainWipedOutboundMessages = nil
        self.doSendReadReceipt = nil
        self.muteNotificationsEndDate = nil
        self.mentionNotificationMode = .globalDefault
    }
    
}


// MARK: - Convenience DB getters

extension PersistedDiscussionLocalConfiguration {
    
    struct Predicate {
        enum Key: String {
            case muteNotificationsEndDate = "muteNotificationsEndDate"
            case rawPerformInteractionDonation = "rawPerformInteractionDonation"
        }
        static func withMuteNotificationsEndDateLaterThan(_ date: Date) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(withNonNilValueForKey: Key.muteNotificationsEndDate),
                NSPredicate(Key.muteNotificationsEndDate, laterThan: date),
            ])
        }
        static func withMuteNotificationsEndDateEarlierThan(_ date: Date) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(withNonNilValueForKey: Key.muteNotificationsEndDate),
                NSPredicate(Key.muteNotificationsEndDate, earlierThan: date),
            ])
        }
        static func withObjectID(objectID: TypeSafeManagedObjectID<PersistedDiscussionLocalConfiguration>) -> NSPredicate {
            NSPredicate(withObjectID: objectID.objectID)
        }
    }
    
    
    @nonobjc class func fetchRequest() -> NSFetchRequest<PersistedDiscussionLocalConfiguration> {
        return NSFetchRequest<PersistedDiscussionLocalConfiguration>(entityName: self.entityName)
    }
    
    
    public static func get(with objectID: TypeSafeManagedObjectID<PersistedDiscussionLocalConfiguration>, within context: NSManagedObjectContext) throws -> PersistedDiscussionLocalConfiguration? {
        let request: NSFetchRequest<PersistedDiscussionLocalConfiguration> = PersistedDiscussionLocalConfiguration.fetchRequest()
        request.predicate = Predicate.withObjectID(objectID: objectID)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
    

    /// Sets back to `nil` the `muteNotificationsEndDate` attribute of all `PersistedDiscussionLocalConfiguration` if it has expired (i.e., if it is earlier than now).
    public static func deleteAllExpiredMuteNotifications(within obvContext: ObvContext) throws {
        let now = Date()
        let request: NSFetchRequest<PersistedDiscussionLocalConfiguration> = PersistedDiscussionLocalConfiguration.fetchRequest()
        request.predicate = Predicate.withMuteNotificationsEndDateEarlierThan(now)
        request.fetchBatchSize = 100
        let items = try obvContext.context.fetch(request)
        items.forEach {
            assert($0.muteNotificationsEndDate != nil && $0.muteNotificationsEndDate! < now)
            $0.muteNotificationsEndDate = nil
        }
    }

    
    /// Returns the earliest mute expiration date occuring later than the requested date, regardless of the owned identity, i.e., considering all persisted discussions.
    public static func getEarliestMuteExpirationDate(laterThan date: Date, within context: NSManagedObjectContext) throws -> Date? {
        let request: NSFetchRequest<PersistedDiscussionLocalConfiguration> = PersistedDiscussionLocalConfiguration.fetchRequest()
        request.predicate = Predicate.withMuteNotificationsEndDateLaterThan(date)
        request.sortDescriptors = [NSSortDescriptor(key: Predicate.Key.muteNotificationsEndDate.rawValue, ascending: true)]
        request.fetchLimit = 1
        return try context.fetch(request).first?.muteNotificationsEndDate
    }
    
}


// MARK: - Reacting to changes

extension PersistedDiscussionLocalConfiguration {
    
    public override func didSave() {
        super.didSave()
        
        defer {
            updatedLocalConfigurationValueTypes.removeAll()
            isInsertedWhileRestoringSyncSnapshot = false
        }
        
        guard !isInsertedWhileRestoringSyncSnapshot else {
            assert(isInserted)
            let log = OSLog(subsystem: ObvUICoreDataConstants.logSubsystem, category: String(describing: Self.self))
            os_log("Insertion of a PersistedDiscussionLocalConfiguration during a snapshot restore --> we don't send any notification", log: log, type: .info)
            return
        }

        if !isDeleted {
           
            let localConfigurationObjectID = self.typedObjectID
            
            for valueType in updatedLocalConfigurationValueTypes {
                
                let value: PersistedDiscussionLocalConfigurationValue
                switch valueType {
                case .autoRead:
                    value = .autoRead(self.autoRead) // ok
                case .retainWipedOutboundMessages:
                    value = .retainWipedOutboundMessages(self.retainWipedOutboundMessages) // ok
                case .doSendReadReceipt:
                    value = .doSendReadReceipt(self.doSendReadReceipt) // ok
                case .mentionNotificationMode:
                    value = .mentionNotificationMode(self.mentionNotificationMode)
                case .countBasedRetentionIsActive:
                    value = .countBasedRetentionIsActive(self.countBasedRetentionIsActive) // ok
                case .countBasedRetention:
                    value = .countBasedRetention(self.countBasedRetention) // ok
                case .timeBasedRetention:
                    value = .timeBasedRetention(self.timeBasedRetention) // ok
                case .muteNotificationsEndDate:
                    value = .muteNotificationsEndDate(self.muteNotificationsEndDate) // ok
                case .defaultEmoji:
                    value = .defaultEmoji(self.defaultEmoji) // ok
                case .notificationSound:
                    value = .notificationSound(self.notificationSound) // ok
                case .performInteractionDonation:
                    value = .performInteractionDonation(self.performInteractionDonation) // ok
                }
                
                ObvMessengerCoreDataNotification.discussionLocalConfigurationHasBeenUpdated(
                    newValue: value,
                    localConfigurationObjectID: localConfigurationObjectID)
                .postOnDispatchQueue()
                
                do {
                    guard let discussionIdentifier = try self.discussion?.discussionIdentifier else {
                        throw ObvUICoreDataError.discussionIsNil
                    }
                    Task { await Self.observersHolder.aPersistedDiscussionLocalConfigurationWasUpdated(discussionIdentifier: discussionIdentifier, value: value) }
                } catch {
                    Self.logger.error("Could not compute discussion identifier: \(error)")
                    assertionFailure()
                }
                
            }
                        
        }
        
    }
    
}

// MARK: - For Backup purposes

extension PersistedDiscussionLocalConfiguration {

    func setMuteNotificationsEndDate(with muteNotificationsEndDate: Date) {
        self.muteNotificationsEndDate = muteNotificationsEndDate
    }
}


// MARK: - For snapshot purposes

extension PersistedDiscussionLocalConfiguration {
    
    var syncSnapshotNode: PersistedDiscussionLocalConfigurationSyncSnapshotItem {
        .init(doSendReadReceipt: doSendReadReceipt)
    }
    
}


struct PersistedDiscussionLocalConfigurationSyncSnapshotItem: Codable, Hashable {

    private let doSendReadReceipt: Bool?
    
    init(doSendReadReceipt: Bool?) {
        self.doSendReadReceipt = doSendReadReceipt
    }

    enum CodingKeys: String, CodingKey, CaseIterable, Codable {
        case doSendReadReceipt = "send_read_receipt"
    }

    // Synthesized implementation of encode(to encoder: Encoder)
    
    // Synthesized implementation of init(from decoder: Decoder)

    func useToUpdate(_ configuration: PersistedDiscussionLocalConfiguration) {
        _ = configuration.setDoSendReadReceipt(to: doSendReadReceipt)
    }
    
}


// MARK: - PersistedDiscussionLocalConfiguration observers

public protocol PersistedDiscussionLocalConfigurationObserver {
    func aPersistedDiscussionLocalConfigurationWasUpdated(discussionIdentifier: ObvDiscussionIdentifier, value: PersistedDiscussionLocalConfigurationValue) async
}


private actor PersistedDiscussionLocalConfigurationObserversHolder: PersistedDiscussionLocalConfigurationObserver {
    
    private var observers = [PersistedDiscussionLocalConfigurationObserver]()
    
    func addObserver(_ newObserver: PersistedDiscussionLocalConfigurationObserver) {
        self.observers.append(newObserver)
    }
    
    // Implementing PersistedDiscussionLocalConfigurationObserver
    
    func aPersistedDiscussionLocalConfigurationWasUpdated(discussionIdentifier: ObvDiscussionIdentifier, value: PersistedDiscussionLocalConfigurationValue) async {
        for observer in observers {
            await observer.aPersistedDiscussionLocalConfigurationWasUpdated(discussionIdentifier: discussionIdentifier, value: value)
        }
    }
        
}
