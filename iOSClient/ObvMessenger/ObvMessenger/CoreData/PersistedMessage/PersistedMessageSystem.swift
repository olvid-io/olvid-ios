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
import ObvEngine
import os.log
import OlvidUtils


@objc(PersistedMessageSystem)
final class PersistedMessageSystem: PersistedMessage, ObvErrorMaker {

    private static let optionalCallLogItemKey = "optionalCallLogItem"
    static let entityName = "PersistedMessageSystem"
    private static let ownedIdentityKey = [PersistedMessage.Predicate.Key.discussion.rawValue, PersistedDiscussion.Predicate.Key.ownedIdentity.rawValue].joined(separator: ".")
    private static let callReportKindKey = [optionalCallLogItemKey, PersistedCallLogContact.rawReportKindKey].joined(separator: ".")
    private static let rawCategoryKey = "rawCategory"
    
    private static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: "PersistedMessageSystem")

    static let errorDomain = "PersistedMessageSystem"
    
    // MARK: System message categories

    enum Category: Int, CustomStringConvertible, CaseIterable {
        case contactJoinedGroup = 0
        case contactLeftGroup = 1
        case numberOfNewMessages = 2
        case discussionIsEndToEndEncrypted = 3
        case contactWasDeleted = 4
        case callLogItem = 5
        case updatedDiscussionSharedSettings = 6
        case discussionWasRemotelyWiped = 7
        case contactRevokedByIdentityProvider = 8
        case notPartOfTheGroupAnymore = 9
        case rejoinedGroup = 10
        case contactIsOneToOneAgain = 11
        case membersOfGroupV2WereUpdated = 12
        case ownedIdentityIsPartOfGroupV2Admins = 13
        case ownedIdentityIsNoLongerPartOfGroupV2Admins = 14


        var description: String {
            switch self {
            case .contactJoinedGroup: return "contactJoinedGroup"
            case .contactLeftGroup: return "contactLeftGroup"
            case .numberOfNewMessages: return "numberOfNewMessages"
            case .discussionIsEndToEndEncrypted: return "discussionIsEndToEndEncrypted"
            case .contactWasDeleted: return "contactWasDeleted"
            case .callLogItem: return "callLogItem"
            case .updatedDiscussionSharedSettings: return "updatedDiscussionSharedSettings"
            case .discussionWasRemotelyWiped: return "discussionWasRemotelyWiped"
            case .contactRevokedByIdentityProvider: return "contactRevokedByIdentityProvider"
            case .notPartOfTheGroupAnymore: return "notPartOfTheGroupAnymore"
            case .rejoinedGroup: return "rejoinedGroup"
            case .contactIsOneToOneAgain: return "contactIsOneToOneAgain"
            case .membersOfGroupV2WereUpdated: return "membersOfGroupV2WereUpdated"
            case .ownedIdentityIsPartOfGroupV2Admins: return "ownedIdentityIsPartOfGroupV2Admins"
            case .ownedIdentityIsNoLongerPartOfGroupV2Admins: return "ownedIdentityIsNoLongerPartOfGroupV2Admins"
            }
        }

        var isCallMessageSystem: Bool {
            switch self {
            case .callLogItem:
                return true
                
            case .contactJoinedGroup,
                    .contactLeftGroup,
                    .numberOfNewMessages,
                    .discussionIsEndToEndEncrypted,
                    .contactWasDeleted,
                    .discussionWasRemotelyWiped,
                    .updatedDiscussionSharedSettings,
                    .contactRevokedByIdentityProvider,
                    .notPartOfTheGroupAnymore,
                    .rejoinedGroup,
                    .contactIsOneToOneAgain,
                    .membersOfGroupV2WereUpdated,
                    .ownedIdentityIsPartOfGroupV2Admins,
                    .ownedIdentityIsNoLongerPartOfGroupV2Admins:
                return false
            }
        }

        var isRelevantForIllustrativeMessage: Bool {
            switch self {
            case .contactJoinedGroup,
                    .contactLeftGroup,
                    .contactWasDeleted,
                    .callLogItem,
                    .updatedDiscussionSharedSettings,
                    .discussionWasRemotelyWiped,
                    .contactRevokedByIdentityProvider,
                    .notPartOfTheGroupAnymore,
                    .rejoinedGroup,
                    .contactIsOneToOneAgain,
                    .membersOfGroupV2WereUpdated,
                    .ownedIdentityIsPartOfGroupV2Admins,
                    .ownedIdentityIsNoLongerPartOfGroupV2Admins:
                return true
                
            case .numberOfNewMessages,
                    .discussionIsEndToEndEncrypted:
                return false
            }
        }

        var isRelevantForCountingUnread: Bool {
            switch self {
            case .contactJoinedGroup: return true
            case .contactLeftGroup: return true
            case .contactWasDeleted: return true
            case .callLogItem: return false // Only if item.callLogReport.isRelevantForCountingUnread
            case .updatedDiscussionSharedSettings: return true
            case .discussionWasRemotelyWiped: return true
            case .contactRevokedByIdentityProvider: return true
            case .notPartOfTheGroupAnymore: return true
            case .rejoinedGroup: return true
            case .contactIsOneToOneAgain: return true
            case .membersOfGroupV2WereUpdated: return true
            case .ownedIdentityIsPartOfGroupV2Admins: return true
            case .ownedIdentityIsNoLongerPartOfGroupV2Admins: return true

            case .numberOfNewMessages: return false
            case .discussionIsEndToEndEncrypted: return false
            }
        }

        static func buildPredicate(with isIncluded: (Category) -> Bool) -> NSPredicate {
            return NSCompoundPredicate(orPredicateWithSubpredicates: Category.allCases
                                    .filter({ isIncluded($0) })
                                    .map({
                                        NSPredicate(format: "%K == %d", PersistedMessageSystem.rawCategoryKey, $0.rawValue)
                                    }))
        }
    }

    enum MessageStatus: Int {
        case new = 0
        case read = 1
    }

    // MARK: - Attributes

    @NSManaged var rawCategory: Int
    @NSManaged private var associatedData: Data?
    @NSManaged private(set) var numberOfUnreadReceivedMessages: Int // Only used when the message is of the category numberOfUnreadMessages.

    // MARK: - Relationships
    
    @NSManaged private(set) var optionalContactIdentity: PersistedObvContactIdentity?
    @NSManaged private(set) var optionalCallLogItem: PersistedCallLogItem?

    // MARK: - Computed variables

    override var kind: PersistedMessageKind { .system }

    override var isNumberOfNewMessagesMessageSystem: Bool {
        return category == .numberOfNewMessages
    }

    var category: Category {
        get {
            return Category(rawValue: self.rawCategory)!
        }
        set {
            self.rawCategory = newValue.rawValue
        }
    }

    var status: MessageStatus {
        get {
            return MessageStatus(rawValue: self.rawStatus)!
        }
        set {
            self.rawStatus = newValue.rawValue
        }
    }
    
    /// Always nil unless the category is `updatedDiscussionSharedSettings`, in which case this variable might be non-nil.
    var expirationJSON: ExpirationJSON? {
        guard category == .updatedDiscussionSharedSettings else { return nil }
        guard let raw = associatedData else { return nil }
        return try? ExpirationJSON.jsonDecode(raw)
    }

    override var textBody: String? {
        let df = DateFormatter()
        df.doesRelativeDateFormatting = false
        df.dateStyle = Calendar.current.isDateInToday(self.timestamp) ? .none : .medium
        df.timeStyle = .short
        let dateString = df.string(from: self.timestamp)
        let contactDisplayName = self.optionalContactIdentity?.customDisplayName ?? self.optionalContactIdentity?.identityCoreDetails.getDisplayNameWithStyle(.full) ?? CommonString.deletedContact
        switch self.category {
        case .ownedIdentityIsPartOfGroupV2Admins:
            return Strings.ownedIdentityIsPartOfGroupV2Admins
        case .ownedIdentityIsNoLongerPartOfGroupV2Admins:
            return Strings.ownedIdentityIsNoLongerPartOfGroupV2Admins
        case .membersOfGroupV2WereUpdated:
            return Strings.membersOfGroupV2WereUpdated
        case .contactJoinedGroup:
            return Strings.contactJoinedGroup(contactDisplayName, dateString)
        case .contactLeftGroup:
            return Strings.contactLeftGroup(contactDisplayName, dateString)
        case .numberOfNewMessages:
            return Strings.numberOfNewMessages(self.numberOfUnreadReceivedMessages)
        case .discussionIsEndToEndEncrypted:
            return Strings.discussionIsEndToEndEncrypted
        case .contactWasDeleted:
            return Strings.contactWasDeleted
        case .updatedDiscussionSharedSettings:
            return Strings.updatedDiscussionSettings
        case .contactRevokedByIdentityProvider:
            return Strings.contactRevokedByIdentityProvider
        case .notPartOfTheGroupAnymore:
            return Strings.notPartOfTheGroupAnymore
        case .rejoinedGroup:
            return Strings.rejoinedGroup
        case .contactIsOneToOneAgain:
            switch try? discussion.kind {
            case .oneToOne(withContactIdentity: let contactIdentity):
                if let contactIdentity = contactIdentity {
                    return Strings.contactIsOneToOneAgain(contactName: contactIdentity.customOrNormalDisplayName)
                } else if let associatedData = associatedData, let contactName = String(data: associatedData, encoding: .utf8)?.trimmingWhitespacesAndNewlines() {
                    return Strings.contactIsOneToOneAgain(contactName: contactName)
                } else {
                    assertionFailure()
                    return nil
                }
            case .groupV1, .groupV2, .none:
                assertionFailure()
                return nil
            }
        case .discussionWasRemotelyWiped:
            let df = DateFormatter()
            df.doesRelativeDateFormatting = false
            df.dateStyle = .medium
            df.timeStyle = .short
            let dateString = df.string(from: self.timestamp)
            return Strings.discussionWasRemotelyWiped(contactDisplayName, dateString)
        case .callLogItem:
            guard let item = optionalCallLogItem,
                  let callLogReport = item.callReportKind else {
                      return nil
                  }
            var participantsCount = item.logContacts.count + item.unknownContactsCount
            if let initialParticipantCount = item.initialParticipantCount,
               [.missedIncomingCall, .rejectedIncomingCall].contains(callLogReport) {
                participantsCount += initialParticipantCount - 1
            }
            var oneParticipant: String?
            if participantsCount > 1 || item.groupIdentifier != nil {
                let sortedLogContacts = item.logContacts.sorted {
                    if $0.isCaller { return true }
                    if $1.isCaller { return false }
                    guard let contactIdentity0 = $0.contactIdentity else { return true }
                    guard let contactIdentity1 = $1.contactIdentity else { return false }
                    return contactIdentity0.sortDisplayName < contactIdentity1.sortDisplayName
                }
                if let firstContact = sortedLogContacts.compactMap({ $0.contactIdentity }).first {
                    oneParticipant = firstContact.customDisplayName ?? firstContact.fullDisplayName
                    participantsCount -= 1
                }
            } else {
                participantsCount = 0
            }
            let content = CallMessageContent(dateString: dateString,
                                             isIncoming: item.isIncoming,
                                             participant: oneParticipant,
                                             othersCount: participantsCount,
                                             duration: item.duration)
            switch callLogReport {
            case .missedIncomingCall:
                return Strings.missedIncomingCall(content)
            case .rejectedIncomingCall:
                return Strings.rejectedIncomingCall(content)
            case .acceptedIncomingCall:
                return Strings.acceptedIncomingCall(content)
            case .acceptedOutgoingCall:
                return Strings.acceptedOutgoingCall(content)
            case .rejectedOutgoingCall:
                return Strings.rejectedOutgoingCall(content)
            case .busyOutgoingCall:
                return Strings.busyOutgoingCall(content)
            case .unansweredOutgoingCall:
                return Strings.unansweredOutgoingCall(content)
            case .uncompletedOutgoingCall:
                return Strings.uncompletedOutgoingCall(content)
            case .rejectedIncomingCallBecauseOfDeniedRecordPermission:
                return Strings.rejectedIncomingCallBecauseOfDeniedRecordPermission(content)
            case .newParticipantInIncomingCall, .newParticipantInOutgoingCall:
                assertionFailure(); return nil
            case .anyIncomingCall:
                return Strings.anyIncomingCall(content)
            case .anyOutgoingCall:
                return Strings.anyOutgoingCall(content)
            case .filteredIncomingCall:
                return Strings.filteredIncomingCall(content)
            }
        }
    }
    
    var textBodyWithoutTimestamp: String? {
        let contactDisplayName = self.optionalContactIdentity?.customDisplayName ?? self.optionalContactIdentity?.identityCoreDetails.getDisplayNameWithStyle(.full) ?? CommonString.deletedContact
        switch self.category {
        case .ownedIdentityIsPartOfGroupV2Admins:
            return Strings.ownedIdentityIsPartOfGroupV2Admins
        case .ownedIdentityIsNoLongerPartOfGroupV2Admins:
            return Strings.ownedIdentityIsNoLongerPartOfGroupV2Admins
        case .membersOfGroupV2WereUpdated:
            return Strings.membersOfGroupV2WereUpdated
        case .contactJoinedGroup:
            return Strings.contactJoinedGroup(contactDisplayName, nil)
        case .contactLeftGroup:
            return Strings.contactLeftGroup(contactDisplayName, nil)
        case .numberOfNewMessages:
            return Strings.numberOfNewMessages(self.numberOfUnreadReceivedMessages)
        case .discussionIsEndToEndEncrypted:
            return Strings.discussionIsEndToEndEncrypted
        case .contactWasDeleted:
            return Strings.contactWasDeleted
        case .updatedDiscussionSharedSettings:
            return Strings.updatedDiscussionSettings
        case .discussionWasRemotelyWiped:
            return Strings.discussionWasRemotelyWiped(contactDisplayName, nil)
        case .contactRevokedByIdentityProvider:
            return Strings.contactRevokedByIdentityProvider
        case .notPartOfTheGroupAnymore:
            return Strings.notPartOfTheGroupAnymore
        case .rejoinedGroup:
            return Strings.rejoinedGroup
        case .contactIsOneToOneAgain:
            return self.textBody
        case .callLogItem:
            guard let item = optionalCallLogItem,
                  let callLogReport = item.callReportKind else {
                return nil
            }
            var participantsCount = item.logContacts.count + item.unknownContactsCount
            if let initialParticipantCount = item.initialParticipantCount,
               [.missedIncomingCall, .rejectedIncomingCall].contains(callLogReport) {
                participantsCount += initialParticipantCount - 1
            }
            var oneParticipant: String?
            if participantsCount > 1 || item.groupIdentifier != nil {
                let sortedLogContacts = item.logContacts.sorted {
                    if $0.isCaller { return true }
                    if $1.isCaller { return false }
                    guard let contactIdentity0 = $0.contactIdentity else { return true }
                    guard let contactIdentity1 = $1.contactIdentity else { return false }
                    return contactIdentity0.sortDisplayName < contactIdentity1.sortDisplayName
                }
                if let firstContact = sortedLogContacts.compactMap({ $0.contactIdentity }).first {
                    oneParticipant = firstContact.customDisplayName ?? firstContact.fullDisplayName
                    participantsCount -= 1
                }
            } else {
                participantsCount = 0
            }
            let content = CallMessageContent(dateString: nil,
                                             isIncoming: item.isIncoming,
                                             participant: oneParticipant,
                                             othersCount: participantsCount,
                                             duration: item.duration)
            switch callLogReport {
            case .missedIncomingCall:
                return Strings.missedIncomingCall(content)
            case .rejectedIncomingCall:
                return Strings.rejectedIncomingCall(content)
            case .acceptedIncomingCall:
                return Strings.acceptedIncomingCall(content)
            case .acceptedOutgoingCall:
                return Strings.acceptedOutgoingCall(content)
            case .rejectedOutgoingCall:
                return Strings.rejectedOutgoingCall(content)
            case .busyOutgoingCall:
                return Strings.busyOutgoingCall(content)
            case .unansweredOutgoingCall:
                return Strings.unansweredOutgoingCall(content)
            case .uncompletedOutgoingCall:
                return Strings.uncompletedOutgoingCall(content)
            case .rejectedIncomingCallBecauseOfDeniedRecordPermission:
                return Strings.rejectedIncomingCallBecauseOfDeniedRecordPermission(content)
            case .newParticipantInIncomingCall, .newParticipantInOutgoingCall:
                assertionFailure(); return nil
            case .anyIncomingCall:
                return Strings.anyIncomingCall(content)
            case .anyOutgoingCall:
                return Strings.anyOutgoingCall(content)
            case .filteredIncomingCall:
                return Strings.filteredIncomingCall(content)
            }
        }
    }

    private var userInfoForDeletion: [String: Any]?

}


// MARK: - Initializer

extension PersistedMessageSystem {
    
    /// At this time, the `messageUploadTimestampFromServer` is only relevant when receiving an `updatedDiscussionSharedSettings` system message.
    convenience init(_ category: Category, optionalContactIdentity: PersistedObvContactIdentity?, optionalCallLogItem: PersistedCallLogItem?, discussion: PersistedDiscussion, messageUploadTimestampFromServer: Date? = nil) throws {
        
        guard category != .numberOfNewMessages else { assertionFailure(); throw PersistedMessageSystem.makeError(message: "Inappropriate initializer called") }
        
        if category != .discussionIsEndToEndEncrypted && discussion.messages.isEmpty {
            try discussion.insertSystemMessagesIfDiscussionIsEmpty(markAsRead: true)
        }
        
        // If we received a timestamp from server, we use it to compute the sort index.
        // Otherwise, we place the system message at the very bottom of the discussion.
        let sortIndex: Double
        if let timestampFromServer = messageUploadTimestampFromServer {
            sortIndex = timestampFromServer.timeIntervalSince1970 as Double
        } else {
            let lastSortIndex = try PersistedMessage.getLargestSortIndex(in: discussion)
            sortIndex = 1/100.0 + ceil(lastSortIndex) // We add "10 milliseconds"
        }
        
        try self.init(timestamp: Date(),
                      body: nil,
                      rawStatus: MessageStatus.new.rawValue,
                      senderSequenceNumber: discussion.lastSystemMessageSequenceNumber + 1,
                      sortIndex: sortIndex,
                      isReplyToAnotherMessage: false,
                      replyTo: nil,
                      discussion: discussion,
                      readOnce: false,
                      visibilityDuration: nil,
                      forwarded: false,
                      forEntityName: PersistedMessageSystem.entityName)
     
        self.rawCategory = category.rawValue
        self.associatedData = nil
        
        self.optionalContactIdentity = optionalContactIdentity
        self.optionalCallLogItem = optionalCallLogItem
        
        discussion.lastSystemMessageSequenceNumber = self.senderSequenceNumber
    }

    /// This initialiser is specific to `numberOfNewMessages` system messages
    ///
    /// - Parameter discussion: The persisted discussion in which a `numberOfNewMessages` should be added
    convenience init(discussion: PersistedDiscussion, sortIndexForFirstNewMessageLimit: Double, timestamp: Date, numberOfNewMessages: Int) throws {
        
        assert(Thread.isMainThread)
        
        guard let context = discussion.managedObjectContext else {
            assertionFailure()
            throw PersistedMessageSystem.makeError(message: "Could not find context")
        }
        
        guard context.concurrencyType == NSManagedObjectContextConcurrencyType.mainQueueConcurrencyType else {
            assertionFailure()
            throw PersistedMessageSystem.makeError(message: "The number of message system message should exclusively be created on the main thread")
        }
        
        try self.init(timestamp: timestamp,
                      body: nil,
                      rawStatus: MessageStatus.read.rawValue,
                      senderSequenceNumber: 0,
                      sortIndex: sortIndexForFirstNewMessageLimit,
                      isReplyToAnotherMessage: false,
                      replyTo: nil,
                      discussion: discussion,
                      readOnce: false,
                      visibilityDuration: nil,
                      forwarded: false,
                      forEntityName: PersistedMessageSystem.entityName)
        
        self.rawCategory = Category.numberOfNewMessages.rawValue
        self.associatedData = nil
        self.optionalContactIdentity = nil
        
        self.numberOfUnreadReceivedMessages = numberOfNewMessages

    }
    
    static func insertOrUpdateNumberOfNewMessagesSystemMessage(within discussion: PersistedDiscussion, timestamp: Date, sortIndex: Double, appropriateNumberOfNewMessages: Int) throws -> PersistedMessageSystem? {
        assert(Thread.isMainThread)
     
        guard let context = discussion.managedObjectContext else {
            throw makeError(message: "Could not find appropriate NSManagedObjectContext within discussion object")
        }
        guard context.concurrencyType == NSManagedObjectContextConcurrencyType.mainQueueConcurrencyType else {
            assertionFailure()
            throw makeError(message: "insertNumberOfNewMessagesSystemMessage should be called on the main thread")
        }

        // If there already exist a PersistedMessageSystem showing new messages and if its sort index is already correct, we update it and return immediately.
        
        if let existingNumberOfNewMessagesSystemMessage = try PersistedMessageSystem.getNumberOfNewMessagesSystemMessage(in: discussion) {
            existingNumberOfNewMessagesSystemMessage.numberOfUnreadReceivedMessages = appropriateNumberOfNewMessages
            try existingNumberOfNewMessagesSystemMessage.resetSortIndexOfNumberOfNewMessagesSystemMessage(to: sortIndex)
            return existingNumberOfNewMessagesSystemMessage
        } else {
            return try PersistedMessageSystem(discussion: discussion, sortIndexForFirstNewMessageLimit: sortIndex, timestamp: timestamp, numberOfNewMessages: appropriateNumberOfNewMessages)
        }
        
    }
    
    
    /// The `messageUploadTimestampFromServer` parameter is only relevant when the shared configuration was received, not locally created.
    static func insertUpdatedDiscussionSharedSettingsSystemMessage(within discussion: PersistedDiscussion, optionalContactIdentity: PersistedObvContactIdentity?, expirationJSON: ExpirationJSON?, messageUploadTimestampFromServer: Date?) throws {
        let message = try self.init(.updatedDiscussionSharedSettings,
                                    optionalContactIdentity: optionalContactIdentity,
                                    optionalCallLogItem: nil,
                                    discussion: discussion,
                                    messageUploadTimestampFromServer: messageUploadTimestampFromServer)
        message.associatedData = try expirationJSON?.jsonEncode()
    }
    
    
    static func insertDiscussionWasRemotelyWipedSystemMessage(within discussion: PersistedDiscussion, byContact contact: PersistedObvContactIdentity, messageUploadTimestampFromServer: Date?) throws {
        _ = try self.init(.discussionWasRemotelyWiped,
                          optionalContactIdentity: contact,
                          optionalCallLogItem: nil,
                          discussion: discussion,
                          messageUploadTimestampFromServer: messageUploadTimestampFromServer)
    }
    
    
    static func insertNotPartOfTheGroupAnymoreSystemMessage(within discussion: PersistedGroupDiscussion) throws {
        _ = try self.init(.notPartOfTheGroupAnymore,
                          optionalContactIdentity: nil,
                          optionalCallLogItem: nil,
                          discussion: discussion)
    }

    
    static func insertNotPartOfTheGroupAnymoreSystemMessage(within discussion: PersistedGroupV2Discussion) throws {
        _ = try self.init(.notPartOfTheGroupAnymore,
                          optionalContactIdentity: nil,
                          optionalCallLogItem: nil,
                          discussion: discussion)
    }

    
    static func insertRejoinedGroupSystemMessage(within discussion: PersistedGroupDiscussion) throws {
        _ = try self.init(.rejoinedGroup,
                          optionalContactIdentity: nil,
                          optionalCallLogItem: nil,
                          discussion: discussion)
    }

    
    static func insertRejoinedGroupSystemMessage(within discussion: PersistedGroupV2Discussion) throws {
        _ = try self.init(.rejoinedGroup,
                          optionalContactIdentity: nil,
                          optionalCallLogItem: nil,
                          discussion: discussion)
    }

    
    static func insertContactIsOneToOneAgainSystemMessage(within discussion: PersistedOneToOneDiscussion) throws {
        let message = try self.init(.contactIsOneToOneAgain,
                                    optionalContactIdentity: discussion.contactIdentity,
                                    optionalCallLogItem: nil,
                                    discussion: discussion)
        message.associatedData = discussion.contactIdentity?.mediumOriginalName.data(using: .utf8)
    }

    
    static func insertMembersOfGroupV2WereUpdatedSystemMessage(within discussion: PersistedGroupV2Discussion) throws {
        _ = try self.init(.membersOfGroupV2WereUpdated,
                          optionalContactIdentity: nil,
                          optionalCallLogItem: nil,
                          discussion: discussion)
    }

    
    static func insertOwnedIdentityIsPartOfGroupV2AdminsMessage(within discussion: PersistedGroupV2Discussion) throws {
        _ = try self.init(.ownedIdentityIsPartOfGroupV2Admins,
                          optionalContactIdentity: nil,
                          optionalCallLogItem: nil,
                          discussion: discussion)
    }

    
    static func insertOwnedIdentityIsNoLongerPartOfGroupV2AdminsMessage(within discussion: PersistedGroupV2Discussion) throws {
        _ = try self.init(.ownedIdentityIsNoLongerPartOfGroupV2Admins,
                          optionalContactIdentity: nil,
                          optionalCallLogItem: nil,
                          discussion: discussion)
    }

}


// MARK: - Other methods

extension PersistedMessageSystem {
    
    func updateAndPotentiallyDeleteNumberOfUnreadReceivedMessagesSystemMessage(newNumberOfUnreadReceivedMessages: Int) {
        assert(Thread.isMainThread)
        guard self.category == .numberOfNewMessages else { assertionFailure(); return }
        if newNumberOfUnreadReceivedMessages <= 0 {
            ObvStack.shared.viewContext.delete(self)
        } else {
            self.numberOfUnreadReceivedMessages = newNumberOfUnreadReceivedMessages
        }
    }
    
    var isRelevantForCountingUnread: Bool {
        if category.isRelevantForCountingUnread { return true }
        if category.isCallMessageSystem {
            return optionalCallLogItem?.callReportKind?.isRelevantForCountingUnread ?? false
        }
        return false
    }
    
}


// MARK: - Determining actions availability

extension PersistedMessageSystem {
    
    var infoActionCanBeMadeAvailableForSystemMessage: Bool {
        return ObvMessengerConstants.developmentMode && category == .callLogItem
    }
    
    var callActionCanBeMadeAvailableForSystemMessage: Bool {
        guard category == .callLogItem else { return false }
        guard optionalCallLogItem != nil else { return false }
        return discussion.isCallAvailable
    }
    
}



// MARK: - Convenience DB getters

extension PersistedMessageSystem {
    
    struct Predicate {
        static var isNew: NSPredicate { NSPredicate(format: "%K == %d", PersistedMessageSystem.rawStatusKey, MessageStatus.new.rawValue) }
        static func inDiscussion(_ discussion: PersistedDiscussion) -> NSPredicate { NSPredicate(format: "%K == %@", PersistedMessage.Predicate.Key.discussion.rawValue, discussion) }
        static func inDiscussionObjectID(_ discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>) -> NSPredicate { NSPredicate(format: "%K == %@", PersistedMessage.Predicate.Key.discussion.rawValue, discussionObjectID.objectID) }
        static var isNumberOfNewMessages: NSPredicate { NSPredicate(format: "%K == %d", PersistedMessageSystem.rawCategoryKey, Category.numberOfNewMessages.rawValue) }
        static var isContactJoinedGroup: NSPredicate { NSPredicate(format: "%K == %d", PersistedMessageSystem.rawCategoryKey, Category.contactJoinedGroup.rawValue) }
        static var isContactLeftGroup: NSPredicate { NSPredicate(format: "%K == %d", PersistedMessageSystem.rawCategoryKey, Category.contactLeftGroup.rawValue) }
        static var isContactWasDeleted: NSPredicate { NSPredicate(format: "%K == %d", PersistedMessageSystem.rawCategoryKey, Category.contactWasDeleted.rawValue) }
        static var isCallMessageSystem: NSPredicate { Category.buildPredicate(with: { $0.isCallMessageSystem }) }
        static var isUpdatedDiscussionSharedSettings: NSPredicate { NSPredicate(format: "%K == %d", PersistedMessageSystem.rawCategoryKey, Category.updatedDiscussionSharedSettings.rawValue) }
        static var isDiscussionIsEndToEndEncrypted: NSPredicate { NSPredicate(format: "%K == %d", PersistedMessageSystem.rawCategoryKey, Category.discussionIsEndToEndEncrypted.rawValue) }
        static var isDiscussionWasRemotelyWiped: NSPredicate { NSPredicate(format: "%K == %d", PersistedMessageSystem.rawCategoryKey, Category.discussionWasRemotelyWiped.rawValue) }
        static func withOwnedIdentity(for ownedIdentity: PersistedObvOwnedIdentity) -> NSPredicate { NSPredicate(format: "%K == %@", PersistedMessageSystem.ownedIdentityKey, ownedIdentity) }
        static var isRelevantForCountingUnread: NSPredicate {
            NSCompoundPredicate(orPredicateWithSubpredicates: [
                Category.buildPredicate(with: { $0.isRelevantForCountingUnread }),
                isCallReportIsRelevantForIllustrativeMessage
            ])
        }
        static var isCallReportIsRelevantForIllustrativeMessage: NSPredicate {
            var predicates = [NSPredicate]()
            for reportKind in CallReportKind.allCases {
                if reportKind.isRelevantForCountingUnread {
                    predicates += [NSPredicate(format: "%K == %d", PersistedMessageSystem.callReportKindKey, reportKind.rawValue)]
                }
            }
            return NSCompoundPredicate(orPredicateWithSubpredicates: predicates)
        }
        static var isRelevantForIllustrativeMessage: NSPredicate {
            NSCompoundPredicate(orPredicateWithSubpredicates: [
                Category.buildPredicate(with: { $0.isRelevantForIllustrativeMessage }),
                isCallReportIsRelevantForIllustrativeMessage
            ])
        }
        static var isDisussionUnmuted: NSPredicate {
            return NSPredicate(format: "%K == nil OR %K < %@", muteNotificationsEndDateKey, muteNotificationsEndDateKey, Date() as NSDate)
        }
        static var hasOptionalCallLogItem: NSPredicate {
            NSPredicate(format: "%K != NIL", PersistedMessageSystem.optionalCallLogItemKey)
        }
        static func hasCallReportKind(_ callReportKind: CallReportKind) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "%K != NIL", PersistedMessageSystem.optionalCallLogItemKey),
                NSPredicate(format: "%K == %d", PersistedMessageSystem.callReportKindKey, callReportKind.rawValue),
            ])
        }
    }
    
    @nonobjc static func fetchRequest() -> NSFetchRequest<PersistedMessageSystem> {
        return NSFetchRequest<PersistedMessageSystem>(entityName: PersistedMessageSystem.entityName)
    }

    static func markAllAsNotNew(within discussion: PersistedDiscussion) throws {
        os_log("Call to markAllAsNotNew in PersistedMessageSystem for discussion %{public}@", log: log, type: .debug, discussion.objectID.debugDescription)
        guard let context = discussion.managedObjectContext else { return }
        let request: NSFetchRequest<PersistedMessageSystem> = PersistedMessageSystem.fetchRequest()
        request.includesSubentities = true
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.inDiscussion(discussion),
            Predicate.isNew,
        ])
        let messages = try context.fetch(request)
        guard !messages.isEmpty else { return }
        messages.forEach { $0.status = .read }
    }

    static func markAsRead(messagesWithObjectIDs: Set<NSManagedObjectID>, within discussion: PersistedDiscussion) throws {
        guard let context = discussion.managedObjectContext else { return }
        let request: NSFetchRequest<PersistedMessageSystem> = PersistedMessageSystem.fetchRequest()
        request.includesSubentities = true
        request.predicate = NSPredicate(format: "SELF IN %@ AND %K == %@ AND %K != %d",
                                        messagesWithObjectIDs,
                                        PersistedMessage.Predicate.Key.discussion.rawValue, discussion,
                                        rawStatusKey, MessageStatus.read.rawValue)
        let messages = try context.fetch(request)
        messages.forEach { $0.status = .read }
    }
    
    static func removeAnyNewMessagesSystemMessages(withinDiscussion discussion: PersistedDiscussion) throws {
        assert(Thread.isMainThread)
        guard let context = discussion.managedObjectContext else {
            throw makeError(message: "Could not find appropriate NSManagedObjectContext within discussion object")
        }
        guard context.concurrencyType == NSManagedObjectContextConcurrencyType.mainQueueConcurrencyType else {
            assertionFailure()
            throw makeError(message: "removeAnyNewMessagesSystemMessages should be called on the main thread")
        }
        let request: NSFetchRequest<PersistedMessageSystem> = PersistedMessageSystem.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@ AND %K == %d",
                                        PersistedMessage.Predicate.Key.discussion.rawValue, discussion,
                                        rawCategoryKey, Category.numberOfNewMessages.rawValue)
        let messages = try context.fetch(request)
        for message in messages {
            context.delete(message)
        }
    }

    static func hasRejectedIncomingCallBecauseOfDeniedRecordPermission(within context: NSManagedObjectContext) throws -> Bool {
        let request: NSFetchRequest<PersistedMessageSystem> = PersistedMessageSystem.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.isCallMessageSystem,
            Predicate.hasCallReportKind(.rejectedIncomingCallBecauseOfDeniedRecordPermission),
        ])
        request.fetchLimit = 1
        let count = try context.count(for: request)
        return count != 0
    }
    
    static func getNewMessageSystemMessageObjectID(withinDiscussion discussion: PersistedDiscussion) throws -> NSManagedObjectID? {
        guard let context = discussion.managedObjectContext else { return nil }
        let request: NSFetchRequest<PersistedMessageSystem> = PersistedMessageSystem.fetchRequest()
        request.predicate = NSPredicate(format: "%K == %@ AND %K == %d",
                                        PersistedMessage.Predicate.Key.discussion.rawValue, discussion,
                                        rawCategoryKey, Category.numberOfNewMessages.rawValue)
        request.fetchLimit = 1
        let messages = try context.fetch(request)
        return messages.first?.objectID
    }

    static func countNew(within discussion: PersistedDiscussion) throws -> Int {
        guard let context = discussion.managedObjectContext else { throw Self.makeError(message: "Could not find context") }
        let request: NSFetchRequest<PersistedMessageSystem> = PersistedMessageSystem.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.isNew,
            Predicate.inDiscussion(discussion),
            Predicate.isRelevantForCountingUnread,
        ])
        return try context.count(for: request)
    }
    
    static func countNew(for ownedIdentity: PersistedObvOwnedIdentity) throws -> Int {
        guard let context = ownedIdentity.managedObjectContext else { throw NSError() }
        let request: NSFetchRequest<PersistedMessageSystem> = PersistedMessageSystem.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.isNew,
            Predicate.withOwnedIdentity(for: ownedIdentity),
            Predicate.isDisussionUnmuted,
            Predicate.isRelevantForCountingUnread,
        ])
        return try context.count(for: request)
    }

    static func countNewForAllOwnedIdentities(within context: NSManagedObjectContext) throws -> Int {
        let request: NSFetchRequest<PersistedMessageSystem> = PersistedMessageSystem.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.isNew,
            Predicate.isDisussionUnmuted,
            Predicate.isRelevantForCountingUnread,
        ])
        return try context.count(for: request)
    }

    static func getFirstNewRelevantSystemMessage(in discussion: PersistedDiscussion) throws -> PersistedMessageSystem? {
        guard let context = discussion.managedObjectContext else { throw makeError(message: "Could not find context in discussion")}
        let request: NSFetchRequest<PersistedMessageSystem> = PersistedMessageSystem.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.isNew,
            Predicate.inDiscussion(discussion),
            Predicate.isRelevantForCountingUnread,
        ])
        request.sortDescriptors = [NSSortDescriptor(key: sortIndexKey, ascending: true)]
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
    
    static func countNewRelevantSystemMessages(in discussion: PersistedDiscussion) throws -> Int {
        guard let context = discussion.managedObjectContext else { throw makeError(message: "Could not find context in discussion")}
        let request: NSFetchRequest<PersistedMessageSystem> = PersistedMessageSystem.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.isNew,
            Predicate.inDiscussion(discussion),
            Predicate.isRelevantForCountingUnread,
        ])
        return try context.count(for: request)
    }
    
    static func getAllNewRelevantSystemMessages(in discussion: PersistedDiscussion) throws -> [PersistedMessageSystem] {
        guard let context = discussion.managedObjectContext else { throw makeError(message: "Could not find context in discussion object") }
        let request: NSFetchRequest<PersistedMessageSystem> = PersistedMessageSystem.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.isNew,
            Predicate.inDiscussion(discussion),
            Predicate.isRelevantForCountingUnread,
        ])
        return try context.fetch(request)
    }

    static func getNumberOfNewMessagesSystemMessage(in discussion: PersistedDiscussion) throws -> PersistedMessageSystem? {
        guard let context = discussion.managedObjectContext else { throw makeError(message: "Could not find context in discussion")}
        let request: NSFetchRequest<PersistedMessageSystem> = PersistedMessageSystem.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.inDiscussion(discussion),
            Predicate.isNumberOfNewMessages,
        ])
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
    
}


// MARK: - Sending notifications on change

extension PersistedMessageSystem {
    
    override func prepareForDeletion() {
        super.prepareForDeletion()
        userInfoForDeletion = ["objectID": objectID,
                               "discussionObjectID": discussion.typedObjectID]
    }
   
    override func didSave() {
        super.didSave()
        
        defer {
            self.userInfoForDeletion = nil
        }
     
        if isDeleted, let userInfoForDeletion = self.userInfoForDeletion {
            guard let objectID = userInfoForDeletion["objectID"] as? NSManagedObjectID,
                  let discussionObjectID = userInfoForDeletion["discussionObjectID"] as? TypeSafeManagedObjectID<PersistedDiscussion> else {
                assertionFailure()
                return
            }
            ObvMessengerCoreDataNotification.persistedMessageSystemWasDeleted(objectID: objectID, discussionObjectID: discussionObjectID)
                .postOnDispatchQueue()
        }
    }
}

extension TypeSafeManagedObjectID where T == PersistedMessageSystem {
    var downcast: TypeSafeManagedObjectID<PersistedMessage> {
        TypeSafeManagedObjectID<PersistedMessage>(objectID: objectID)
    }
}
