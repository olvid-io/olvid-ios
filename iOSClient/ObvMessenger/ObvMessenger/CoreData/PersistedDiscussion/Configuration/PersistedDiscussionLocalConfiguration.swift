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


@objc(PersistedDiscussionLocalConfiguration)
final class PersistedDiscussionLocalConfiguration: NSManagedObject {
    
    private static let entityName = "PersistedDiscussionLocalConfiguration"
    static let muteNotificationsEndDateKey = "muteNotificationsEndDate"
    private static func makeError(message: String) -> Error { NSError(domain: "PersistedDiscussionLocalConfiguration", code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }

    // MARK: - Attributes

    @NSManaged private var rawAutoRead: NSNumber?
    @NSManaged private var rawCountBasedRetention: NSNumber?
    @NSManaged var rawCountBasedRetentionIsActive: NSNumber?
    @NSManaged private var rawDoFetchContentRichURLsMetadata: NSNumber?
    @NSManaged private var rawDoSendReadReceipt: NSNumber?
    @NSManaged private var rawTimeBasedRetention: NSNumber?
    @NSManaged var rawRetainWipedOutboundMessages: NSNumber?
    @NSManaged private(set) var defaultEmoji: String?
    @NSManaged private var muteNotificationsEndDate: Date?
    @NSManaged private var rawNotificationSound: String?

    // MARK: - Relationships

    @NSManaged private(set) var discussion: PersistedDiscussion?

    // MARK: - Computed variables

    var autoRead: Bool? {
        get {
            rawAutoRead?.boolValue
        }
        set {
            guard newValue != autoRead else { return }
            rawAutoRead = (newValue == nil ? nil : newValue! as NSNumber)
        }
    }

    /// If `nil`, we should use the app default value. Otherwise, the user did override the default value.
    var countBasedRetentionIsActive: Bool? {
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

    var countBasedRetention: Int? {
        get {
            guard let raw = rawCountBasedRetention else { return nil }
            return raw.intValue
        }
        set {
            guard newValue != countBasedRetention else { return }
            rawCountBasedRetention = (newValue == nil ? nil : max(1, newValue!) as NSNumber)
        }
    }
    
    var timeBasedRetention: DurationOptionAltOverride {
        get {
            guard let seconds = rawTimeBasedRetention?.intValue else { return .useAppDefault }
            return DurationOptionAltOverride(rawValue: seconds) ?? .useAppDefault
        }
        set {
            self.rawTimeBasedRetention = (newValue == .useAppDefault ? nil : NSNumber(value: newValue.rawValue) )
        }
    }

    var doSendReadReceipt: Bool? {
        get {
            rawDoSendReadReceipt?.boolValue
        }
        set {
            guard newValue != doSendReadReceipt else { return }
            rawDoSendReadReceipt = (newValue == nil ? nil : newValue! as NSNumber)
        }
    }
    
    var doFetchContentRichURLsMetadata: ObvMessengerSettings.Discussions.FetchContentRichURLsMetadataChoice? {
        get {
            guard let raw = rawDoFetchContentRichURLsMetadata else { return nil }
            return ObvMessengerSettings.Discussions.FetchContentRichURLsMetadataChoice(rawValue: raw.intValue)
        }
        set {
            guard newValue != doFetchContentRichURLsMetadata else { return }
            rawDoFetchContentRichURLsMetadata = (newValue == nil ? nil : newValue!.rawValue as NSNumber)
        }
    }

    var retainWipedOutboundMessages: Bool? {
        get {
            rawRetainWipedOutboundMessages?.boolValue
        }
        set {
            guard newValue != retainWipedOutboundMessages else { return }
            rawRetainWipedOutboundMessages = (newValue == nil ? nil : newValue! as NSNumber)
        }
    }

    var notificationSound: NotificationSound? {
        get {
            guard let soundIdentifier = rawNotificationSound else { return nil }
            return NotificationSound.allCases.first { $0.identifier == soundIdentifier }
        }
        set {
            if let value = newValue {
                guard value.identifier != rawNotificationSound else { return }
                rawNotificationSound = value.identifier
            } else {
                rawNotificationSound = nil
            }
        }
    }

}

enum PersistedDiscussionLocalConfigurationValue {
    case autoRead(autoRead: Bool?)
    case retainWipedOutboundMessages(retainWipedOutboundMessages: Bool?)
    case doSendReadReceipt(doSendReadReceipt: Bool?)
    case countBasedRetentionIsActive(countBasedRetentionIsActive: Bool?)
    case countBasedRetention(countBasedRetention: Int?)
    case doFetchContentRichURLsMetadata(doFetchContentRichURLsMetadata: ObvMessengerSettings.Discussions.FetchContentRichURLsMetadataChoice?)
    case timeBasedRetention(timeBasedRetention: DurationOptionAltOverride)
    case muteNotificationsDuration(muteNotificationsDuration: MuteDurationOption?)
    case defaultEmoji(emoji: String?)
    case notificationSound(_: NotificationSound?)
}

extension PersistedDiscussionLocalConfigurationValue {

    func sendUpdateRequestNotifications(with objectID: TypeSafeManagedObjectID<PersistedDiscussionLocalConfiguration>) {
        ObvMessengerCoreDataNotification.userWantsToUpdateDiscussionLocalConfiguration(value: self, localConfigurationObjectID: objectID).postOnDispatchQueue()
    }
}

// MARK: Mute Notifications End Date helpers

extension PersistedDiscussionLocalConfiguration {

    var shouldMuteNotifications: Bool {
        guard let muteNotificationsEndDate = muteNotificationsEndDate else { return false }
        return muteNotificationsEndDate > Date()
    }

    var currentMuteNotificationsEndDate: Date? {
        guard shouldMuteNotifications else { return nil }
        return muteNotificationsEndDate
    }

    var isMuteNotificationsEndDateExpired: Bool {
        guard let muteNotificationsEndDate = muteNotificationsEndDate else { return false }
        return muteNotificationsEndDate <= Date()
    }

    func cleanExpiredMuteNotificationsEndDate() {
        guard isMuteNotificationsEndDateExpired else { return }
        self.muteNotificationsEndDate = nil
    }

    static func formatDateForMutedNotification(_ date: Date) -> String {
        let df = DateFormatter()
        df.doesRelativeDateFormatting = false
        df.dateStyle = Calendar.current.isDateInToday(date) ? .none : .medium
        df.timeStyle = .short
        return df.string(from: date)
    }


}


// MARK: Update

extension PersistedDiscussionLocalConfiguration {

    func update(with newValue: PersistedDiscussionLocalConfigurationValue) {
        switch newValue {
        case .autoRead(autoRead: let autoRead):
            self.autoRead = autoRead
        case .retainWipedOutboundMessages(retainWipedOutboundMessages: let retainWipedOutboundMessages):
            self.retainWipedOutboundMessages = retainWipedOutboundMessages
        case .doSendReadReceipt(doSendReadReceipt: let doSendReadReceipt):
            self.doSendReadReceipt = doSendReadReceipt
        case .countBasedRetentionIsActive(countBasedRetentionIsActive: let countBasedRetentionIsActive):
            self.countBasedRetentionIsActive = countBasedRetentionIsActive
        case .countBasedRetention(countBasedRetention: let countBasedRetention):
            self.countBasedRetention = countBasedRetention
        case .doFetchContentRichURLsMetadata(doFetchContentRichURLsMetadata: let doFetchContentRichURLsMetadata):
            self.doFetchContentRichURLsMetadata = doFetchContentRichURLsMetadata
        case .timeBasedRetention(timeBasedRetention: let timeBasedRetention):
            self.timeBasedRetention = timeBasedRetention
        case .muteNotificationsDuration(muteNotificationsDuration: let muteNotificationsDuration):
            if let muteNotificationsDuration = muteNotificationsDuration {
                switch muteNotificationsDuration {
                case .oneHour, .eightHours, .sevenDays:
                    let interval = TimeInterval(muteNotificationsDuration.rawValue)
                    self.muteNotificationsEndDate = Date().addingTimeInterval(interval)
                case .indefinitely:
                    self.muteNotificationsEndDate = Date.distantFuture
                }
            } else {
                self.muteNotificationsEndDate = nil
            }
        case .defaultEmoji(emoji: let emoji):
            self.defaultEmoji = emoji
        case .notificationSound(let notificationSound):
            self.notificationSound = notificationSound
        }
    }

}

// MARK: - Initializer

extension PersistedDiscussionLocalConfiguration {
    
    convenience init(discussion: PersistedDiscussion) throws {
        guard let context = discussion.managedObjectContext else {
            throw Self.makeError(message: "Could not find context")
        }
        let entityDescription = NSEntityDescription.entity(forEntityName: PersistedDiscussionLocalConfiguration.entityName, in: context)!
        self.init(entity: entityDescription, insertInto: context)
        self.discussion = discussion
        self.rawAutoRead = nil
        self.countBasedRetentionIsActive = nil
        self.countBasedRetention = nil
        self.timeBasedRetention = .useAppDefault
        self.rawRetainWipedOutboundMessages = nil
        self.doSendReadReceipt = nil
        self.doFetchContentRichURLsMetadata = nil
        self.muteNotificationsEndDate = nil
    }
    
}


// MARK: - Convenience DB getters

extension PersistedDiscussionLocalConfiguration {

    @nonobjc class func fetchRequest() -> NSFetchRequest<PersistedDiscussionLocalConfiguration> {
        return NSFetchRequest<PersistedDiscussionLocalConfiguration>(entityName: self.entityName)
    }
    
    static func get(with objectID: TypeSafeManagedObjectID<PersistedDiscussionLocalConfiguration>, within context: NSManagedObjectContext) throws -> PersistedDiscussionLocalConfiguration? {
        try context.existingObject(with: objectID.objectID) as? PersistedDiscussionLocalConfiguration
    }

    static func getAll(within context: NSManagedObjectContext) throws -> [PersistedDiscussionLocalConfiguration] {
        let request: NSFetchRequest<PersistedDiscussionLocalConfiguration> = PersistedDiscussionLocalConfiguration.fetchRequest()
        return try context.fetch(request)
    }

    static func getEarliestMuteExpirationDate(laterThan date: Date, within context: NSManagedObjectContext) throws -> Date? {
        let request: NSFetchRequest<PersistedDiscussionLocalConfiguration> = PersistedDiscussionLocalConfiguration.fetchRequest()
        request.predicate = NSPredicate(format: "\(muteNotificationsEndDateKey) > %@", date as NSDate)
        request.sortDescriptors = [NSSortDescriptor(key: muteNotificationsEndDateKey, ascending: true)]
        request.fetchLimit = 1
        return try context.fetch(request).first?.muteNotificationsEndDate

    }


}


// MARK: - Thread safe struct

extension PersistedDiscussionLocalConfiguration {
    
    struct Structure {
        let notificationSound: NotificationSound?
        let shouldMuteNotifications: Bool
    }
    
    func toStructure() throws -> Structure {
        return Structure(notificationSound: notificationSound,
                         shouldMuteNotifications: self.shouldMuteNotifications)
    }
    
}


// MARK: - For Backup purposes

extension PersistedDiscussionLocalConfiguration {

    func setMuteNotificationsEndDate(with muteNotificationsEndDate: Date) {
        self.muteNotificationsEndDate = muteNotificationsEndDate
    }
}
