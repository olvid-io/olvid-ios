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
import ObvEngine
import os.log
import OlvidUtils
import ObvTypes
import ObvSettings
import ObvAppCoreConstants


@objc(PersistedMessageSystem)
public final class PersistedMessageSystem: PersistedMessage, ObvIdentifiableManagedObject {

    public static let entityName = "PersistedMessageSystem"
    private static let log = OSLog(subsystem: ObvUICoreDataConstants.logSubsystem, category: "PersistedMessageSystem")

    // MARK: System message categories

    public enum Category: Int, CustomStringConvertible, CaseIterable {
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
        case ownedIdentityDidCaptureSensitiveMessages = 15
        case contactIdentityDidCaptureSensitiveMessages = 16
        case contactWasIntroducedToAnotherContact = 17


        public var description: String {
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
            case .ownedIdentityDidCaptureSensitiveMessages: return "ownedIdentityDidCaptureSensitiveMessages"
            case .contactIdentityDidCaptureSensitiveMessages: return "contactIdentityDidCaptureSensitiveMessages"
            case .contactWasIntroducedToAnotherContact: return "contactWasIntroducedToAnotherContact"
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
                    .ownedIdentityIsNoLongerPartOfGroupV2Admins,
                    .ownedIdentityDidCaptureSensitiveMessages,
                    .contactIdentityDidCaptureSensitiveMessages,
                    .contactWasIntroducedToAnotherContact:
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
                    .ownedIdentityIsNoLongerPartOfGroupV2Admins,
                    .ownedIdentityDidCaptureSensitiveMessages,
                    .contactIdentityDidCaptureSensitiveMessages,
                    .contactWasIntroducedToAnotherContact:
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
            case .ownedIdentityDidCaptureSensitiveMessages: return true
            case .contactIdentityDidCaptureSensitiveMessages: return true

            case .numberOfNewMessages: return false
            case .discussionIsEndToEndEncrypted: return false
            case .contactWasIntroducedToAnotherContact: return false
            }
        }

        static func buildPredicate(with isIncluded: (Category) -> Bool) -> NSPredicate {
            return NSCompoundPredicate(orPredicateWithSubpredicates: Category.allCases
                .filter({ isIncluded($0) })
                .map({
                    Predicate.withCategory($0)
                }))
        }
    }

    public enum MessageStatus: Int {
        case new = 0
        case read = 1
    }

    // MARK: - Attributes

    @NSManaged private var associatedData: Data?
    @NSManaged public private(set) var numberOfUnreadReceivedMessages: Int // Only used when the message is of the category numberOfUnreadMessages.
    @NSManaged private var optionalOwnedIdentityIdentity: Data? // Used, e.g., to specify that a remote discussion wipe was performed from another owned device
    @NSManaged var rawCategory: Int

    // MARK: - Relationships
    
    @NSManaged public private(set) var optionalContactIdentity: PersistedObvContactIdentity?
    @NSManaged public private(set) var optionalCallLogItem: PersistedCallLogItem?

    // MARK: - Computed variables

    var optionalOwnedCryptoId: ObvCryptoId? {
        get {
            guard let optionalOwnedIdentityIdentity else { return nil }
            guard let ownedCryptoId = try? ObvCryptoId(identity: optionalOwnedIdentityIdentity) else { assertionFailure(); return nil }
            return ownedCryptoId
        }
        set {
            self.optionalOwnedIdentityIdentity = newValue?.getIdentity()
        }
    }
    
    /// Expected to be non-nil, unless this `NSManagedObject` is deleted.
    public var objectPermanentID: ObvManagedObjectPermanentID<PersistedMessageSystem> {
        get throws {
            guard self.managedObjectContext != nil else { assertionFailure(); throw ObvUICoreDataError.noContext }
            return ObvManagedObjectPermanentID<PersistedMessageSystem>(uuid: self.permanentUUID)
        }
    }

    public override var kind: PersistedMessageKind { .system }

    /// 2023-07-17: This is the most appropriate identifier to use in, e.g., notifications
    public override var identifier: MessageIdentifier {
        return .system(id: self.systemMessageIdentifier)
    }
    
    public var systemMessageIdentifier: SystemMessageIdentifier {
        return .objectID(objectID: self.objectID)
    }


    override var isNumberOfNewMessagesMessageSystem: Bool {
        return category == .numberOfNewMessages
    }

    public var category: Category {
        get {
            return Category(rawValue: self.rawCategory)!
        }
        set {
            self.rawCategory = newValue.rawValue
        }
    }

    public private(set) var status: MessageStatus {
        get {
            return MessageStatus(rawValue: self.rawStatus)!
        }
        set {
            self.rawStatus = newValue.rawValue
        }
    }
    
    func markAsRead() {
        if self.status != .read {
            self.status = .read
        }
    }
    
    public func setNumberOfUnreadReceivedMessages(to newValue: Int) {
        assert(Thread.isMainThread, "We do not expect this variable to be set on a background context")
        if self.numberOfUnreadReceivedMessages != newValue {
            self.numberOfUnreadReceivedMessages = newValue
        }
    }
    
    /// Always nil unless the category is `updatedDiscussionSharedSettings`, in which case this variable might be non-nil.
    public var expirationJSON: ExpirationJSON? {
        guard category == .updatedDiscussionSharedSettings else { return nil }
        guard let raw = associatedData else { return nil }
        return try? ExpirationJSON.jsonDecode(raw)
    }

    public override var textBody: String? {
        let df = DateFormatter()
        df.doesRelativeDateFormatting = false
        df.dateStyle = Calendar.current.isDateInToday(self.timestamp) ? .none : .medium
        df.timeStyle = .short
        let dateString = df.string(from: self.timestamp)
        let contactDisplayName: String
        if let optionalContactIdentity {
            contactDisplayName = optionalContactIdentity.customDisplayName ?? optionalContactIdentity.identityCoreDetails?.getDisplayNameWithStyle(.full) ?? CommonString.deletedContact
        } else if optionalOwnedCryptoId != nil {
            contactDisplayName = CommonString.Word.You.lowercased()
        } else {
            contactDisplayName = CommonString.deletedContact
        }        
        switch self.category {
        case .contactWasIntroducedToAnotherContact:
            let discussionContactDisplayName: String? = (discussion as? PersistedOneToOneDiscussion)?.contactIdentity?.customOrShortDisplayName
            let otherContactDisplayName: String? = optionalContactIdentity?.customOrNormalDisplayName
            return Strings.contactWasIntroducedToAnotherContact(discussionContactDisplayName, otherContactDisplayName)
        case .ownedIdentityDidCaptureSensitiveMessages:
            return Strings.ownedIdentityDidCaptureSensitiveMessages
        case .contactIdentityDidCaptureSensitiveMessages:
            let contactDisplayName: String?
            if let optionalContactIdentity {
                contactDisplayName = optionalContactIdentity.customOrShortDisplayName
            } else if let associatedData, let contactName = String(data: associatedData, encoding: .utf8)?.trimmingWhitespacesAndNewlines() {
                contactDisplayName = contactName
            } else {
                assertionFailure()
                contactDisplayName = nil
            }
            return Strings.contactIdentityDidCaptureSensitiveMessages(contactDisplayName)
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
            switch try? discussion?.kind {
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
            case .answeredOnOtherDevice:
                return Strings.answeredOnOtherDevice(content)
            case .rejectedOnOtherDevice:
                return Strings.rejectedOnOtherDevice(content)
            case .rejectedIncomingCallAsTheReceiveCallsOnThisDeviceSettingIsFalse:
                return Strings.rejectedIncomingCallAsTheReceiveCallsOnThisDeviceSettingIsFalse(content)
            }
        }
    }
    
    public var textBodyWithoutTimestamp: String? {
        let contactDisplayName: String
        if let optionalContactIdentity {
            contactDisplayName = optionalContactIdentity.customDisplayName ?? optionalContactIdentity.identityCoreDetails?.getDisplayNameWithStyle(.full) ?? optionalContactIdentity.fullDisplayName
        } else if optionalOwnedCryptoId != nil {
            contactDisplayName = CommonString.Word.You.lowercased()
        } else {
            contactDisplayName = CommonString.deletedContact
        }
        switch self.category {
        case .contactWasIntroducedToAnotherContact:
            return textBody
        case .ownedIdentityDidCaptureSensitiveMessages:
            return textBody
        case .contactIdentityDidCaptureSensitiveMessages:
            return textBody
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
            case .answeredOnOtherDevice:
                return Strings.answeredOnOtherDevice(content)
            case .rejectedOnOtherDevice:
                return Strings.rejectedOnOtherDevice(content)
            case .rejectedIncomingCallAsTheReceiveCallsOnThisDeviceSettingIsFalse:
                return Strings.rejectedIncomingCallAsTheReceiveCallsOnThisDeviceSettingIsFalse(content)
            }
        }
    }

    private var userInfoForDeletion: [String: Any]?

}


// MARK: - Initializer

extension PersistedMessageSystem {
    
    /// At this time, the `messageUploadTimestampFromServer` is only relevant when receiving an `updatedDiscussionSharedSettings` system message.
    public convenience init(_ category: Category, optionalContactIdentity: PersistedObvContactIdentity?, optionalOwnedCryptoId: ObvCryptoId?, optionalCallLogItem: PersistedCallLogItem?, discussion: PersistedDiscussion, messageUploadTimestampFromServer: Date? = nil, timestamp: Date, thisMessageTimestampCanResetDiscussionTimestampOfLastMessage: Bool = true) throws {
        
        guard category != .numberOfNewMessages else { assertionFailure(); throw ObvUICoreDataError.inappropriateInitilizerCalled }
        
        if category != .discussionIsEndToEndEncrypted && discussion.messages.isEmpty {
            try discussion.insertSystemMessagesIfDiscussionIsEmpty(markAsRead: true, messageTimestamp: Date())
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
        
        let senderSequenceNumber = discussion.incrementLastSystemMessageSequenceNumber()
        
        try self.init(timestamp: timestamp,
                      body: nil,
                      rawStatus: MessageStatus.new.rawValue,
                      senderSequenceNumber: senderSequenceNumber,
                      sortIndex: sortIndex,
                      replyTo: nil,
                      discussion: discussion,
                      readOnce: false,
                      visibilityDuration: nil,
                      forwarded: false,
                      mentions: [], // For now, we have no mentions in system messages
                      isLocation: false,
                      thisMessageTimestampCanResetDiscussionTimestampOfLastMessage: thisMessageTimestampCanResetDiscussionTimestampOfLastMessage,
                      forEntityName: PersistedMessageSystem.entityName)
     
        self.rawCategory = category.rawValue
        self.associatedData = nil
        self.optionalOwnedCryptoId = optionalOwnedCryptoId
        
        self.optionalContactIdentity = optionalContactIdentity
        self.optionalCallLogItem = optionalCallLogItem
        
    }

    /// This initialiser is specific to `numberOfNewMessages` system messages
    ///
    /// - Parameter discussion: The persisted discussion in which a `numberOfNewMessages` should be added
    convenience init(discussion: PersistedDiscussion, sortIndexForFirstNewMessageLimit: Double, timestamp: Date, numberOfNewMessages: Int) throws {
        
        assert(Thread.isMainThread)
        
        guard let context = discussion.managedObjectContext else {
            assertionFailure()
            throw ObvUICoreDataError.noContext
        }
        
        guard context.concurrencyType == NSManagedObjectContextConcurrencyType.mainQueueConcurrencyType else {
            assertionFailure()
            throw ObvUICoreDataError.inappropriateContext
        }
        
        try self.init(timestamp: timestamp,
                      body: nil,
                      rawStatus: MessageStatus.read.rawValue,
                      senderSequenceNumber: 0,
                      sortIndex: sortIndexForFirstNewMessageLimit,
                      replyTo: nil,
                      discussion: discussion,
                      readOnce: false,
                      visibilityDuration: nil,
                      forwarded: false,
                      mentions: [], // For now, we have no mentions in system messages,
                      isLocation: false,
                      forEntityName: PersistedMessageSystem.entityName)
        
        self.rawCategory = Category.numberOfNewMessages.rawValue
        self.associatedData = nil
        self.optionalContactIdentity = nil
        
        self.numberOfUnreadReceivedMessages = numberOfNewMessages

    }
    
    public static func insertOrUpdateNumberOfNewMessagesSystemMessage(within discussion: PersistedDiscussion, timestamp: Date, sortIndex: Double, appropriateNumberOfNewMessages: Int) throws -> PersistedMessageSystem? {
        assert(Thread.isMainThread)
     
        guard let context = discussion.managedObjectContext else {
            assertionFailure()
            throw ObvUICoreDataError.noContext
        }
        guard context.concurrencyType == NSManagedObjectContextConcurrencyType.mainQueueConcurrencyType else {
            assertionFailure()
            throw ObvUICoreDataError.inappropriateContext
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
    public static func insertUpdatedDiscussionSharedSettingsSystemMessage(within discussion: PersistedDiscussion, optionalContactIdentity: PersistedObvContactIdentity?, expirationJSON: ExpirationJSON?, messageUploadTimestampFromServer: Date?, markAsRead: Bool) throws {
        let message = try self.init(.updatedDiscussionSharedSettings,
                                    optionalContactIdentity: optionalContactIdentity,
                                    optionalOwnedCryptoId: nil,
                                    optionalCallLogItem: nil,
                                    discussion: discussion,
                                    messageUploadTimestampFromServer: messageUploadTimestampFromServer,
                                    timestamp: Date())
        message.associatedData = try expirationJSON?.jsonEncode()
        if markAsRead {
            message.status = .read
        }
    }
    
    
    public static func insertDiscussionWasRemotelyWipedSystemMessage(within discussion: PersistedDiscussion, byContact contact: PersistedObvContactIdentity, messageUploadTimestampFromServer: Date?) throws {
        _ = try self.init(.discussionWasRemotelyWiped,
                          optionalContactIdentity: contact,
                          optionalOwnedCryptoId: nil,
                          optionalCallLogItem: nil,
                          discussion: discussion,
                          messageUploadTimestampFromServer: messageUploadTimestampFromServer,
                          timestamp: Date())
    }
    
    
    static func insertNotPartOfTheGroupAnymoreSystemMessage(within discussion: PersistedGroupDiscussion) throws {
        _ = try self.init(.notPartOfTheGroupAnymore,
                          optionalContactIdentity: nil,
                          optionalOwnedCryptoId: nil,
                          optionalCallLogItem: nil,
                          discussion: discussion,
                          timestamp: Date())
    }

    
    static func insertNotPartOfTheGroupAnymoreSystemMessage(within discussion: PersistedGroupV2Discussion) throws {
        _ = try self.init(.notPartOfTheGroupAnymore,
                          optionalContactIdentity: nil,
                          optionalOwnedCryptoId: nil,
                          optionalCallLogItem: nil,
                          discussion: discussion,
                          timestamp: Date())
    }

    
    static func insertRejoinedGroupSystemMessage(within discussion: PersistedGroupDiscussion) throws {
        _ = try self.init(.rejoinedGroup,
                          optionalContactIdentity: nil,
                          optionalOwnedCryptoId: nil,
                          optionalCallLogItem: nil,
                          discussion: discussion,
                          timestamp: Date())
    }

    
    static func insertRejoinedGroupSystemMessage(within discussion: PersistedGroupV2Discussion) throws {
        _ = try self.init(.rejoinedGroup,
                          optionalContactIdentity: nil,
                          optionalOwnedCryptoId: nil,
                          optionalCallLogItem: nil,
                          discussion: discussion,
                          timestamp: Date())
    }

    
    static func insertContactIsOneToOneAgainSystemMessage(within discussion: PersistedOneToOneDiscussion) throws {
        let message = try self.init(.contactIsOneToOneAgain,
                                    optionalContactIdentity: discussion.contactIdentity,
                                    optionalOwnedCryptoId: nil,
                                    optionalCallLogItem: nil,
                                    discussion: discussion,
                                    timestamp: Date())
        message.associatedData = discussion.contactIdentity?.mediumOriginalName.data(using: .utf8)
    }

    
    public static func insertMembersOfGroupV2WereUpdatedSystemMessage(within discussion: PersistedGroupV2Discussion) throws {
        _ = try self.init(.membersOfGroupV2WereUpdated,
                          optionalContactIdentity: nil,
                          optionalOwnedCryptoId: nil,
                          optionalCallLogItem: nil,
                          discussion: discussion,
                          timestamp: Date())
    }

    public static func insertMemberOfGroupV2HasJoinedSystemMessage(within discussion: PersistedGroupV2Discussion, memberIdentity: PersistedObvContactIdentity) throws {
        _ = try self.init(.contactJoinedGroup,
                          optionalContactIdentity: memberIdentity,
                          optionalOwnedCryptoId: nil,
                          optionalCallLogItem: nil,
                          discussion: discussion,
                          timestamp: Date())
    }

    public static func insertMemberOfGroupV2HasLeftSystemMessage(within discussion: PersistedGroupV2Discussion, memberIdentity: PersistedObvContactIdentity) throws {
        _ = try self.init(.contactLeftGroup,
                          optionalContactIdentity: memberIdentity,
                          optionalOwnedCryptoId: nil,
                          optionalCallLogItem: nil,
                          discussion: discussion,
                          timestamp: Date())
    }

    public static func insertOwnedIdentityIsPartOfGroupV2AdminsMessage(within discussion: PersistedGroupV2Discussion) throws {
        _ = try self.init(.ownedIdentityIsPartOfGroupV2Admins,
                          optionalContactIdentity: nil,
                          optionalOwnedCryptoId: nil,
                          optionalCallLogItem: nil,
                          discussion: discussion,
                          timestamp: Date())
    }

    
    public static func insertOwnedIdentityIsNoLongerPartOfGroupV2AdminsMessage(within discussion: PersistedGroupV2Discussion) throws {
        _ = try self.init(.ownedIdentityIsNoLongerPartOfGroupV2Admins,
                          optionalContactIdentity: nil,
                          optionalOwnedCryptoId: nil,
                          optionalCallLogItem: nil,
                          discussion: discussion,
                          timestamp: Date())
    }
    
    
    static func insertOwnedIdentityDidCaptureSensitiveMessages(within discussion: PersistedDiscussion) throws {
        _ = try self.init(.ownedIdentityDidCaptureSensitiveMessages,
                          optionalContactIdentity: nil,
                          optionalOwnedCryptoId: nil,
                          optionalCallLogItem: nil,
                          discussion: discussion,
                          timestamp: Date())
    }
    

    static func insertContactIdentityDidCaptureSensitiveMessages(within discussion: PersistedDiscussion, contact: PersistedObvContactIdentity, timestamp: Date) throws {
        // Make a few sanity checks before inserting the system message
        guard discussion.managedObjectContext == contact.managedObjectContext else { assertionFailure(); throw ObvUICoreDataError.inappropriateContext }
        _ = try self.init(.contactIdentityDidCaptureSensitiveMessages,
                          optionalContactIdentity: contact,
                          optionalOwnedCryptoId: nil,
                          optionalCallLogItem: nil,
                          discussion: discussion,
                          timestamp: timestamp)
    }
    
    
    static func insertOwnedIdentityDidCaptureSensitiveMessages(within discussion: PersistedDiscussion, ownedCryptoId: ObvCryptoId, timestamp: Date) throws {
        _ = try self.init(.ownedIdentityDidCaptureSensitiveMessages,
                          optionalContactIdentity: nil,
                          optionalOwnedCryptoId: ownedCryptoId,
                          optionalCallLogItem: nil,
                          discussion: discussion,
                          timestamp: timestamp)
    }

    
    static func insertContactWasIntroducedToAnotherContact(within oneToOneDiscussion: PersistedOneToOneDiscussion, otherContact: PersistedObvContactIdentity) throws {
        guard oneToOneDiscussion.ownedIdentity == otherContact.ownedIdentity else {
            throw ObvUICoreDataError.unexpectedOwnedIdentity
        }
        guard oneToOneDiscussion.contactIdentity != otherContact else {
            throw ObvUICoreDataError.unexpectedContact
        }
        // We set thisMessageTimestampCanResetDiscussionTimestampOfLastMessage to false as we do not want discussions to "move" in the list of recent discussions just because we introduced a contact to another.
        // This would particularly not make sense when introducing one contact to many other contacts.
        _ = try self.init(.contactWasIntroducedToAnotherContact,
                          optionalContactIdentity: otherContact,
                          optionalOwnedCryptoId: nil,
                          optionalCallLogItem: nil,
                          discussion: oneToOneDiscussion,
                          timestamp: Date(),
                          thisMessageTimestampCanResetDiscussionTimestampOfLastMessage: false)
    }
    
}


// MARK: - Other methods

extension PersistedMessageSystem {
        
    public var isRelevantForCountingUnread: Bool {
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
        return ObvAppCoreConstants.appType == .development && category == .callLogItem
    }
    
    var callActionCanBeMadeAvailableForSystemMessage: Bool {
        guard category == .callLogItem else { return false }
        guard optionalCallLogItem != nil else { return false }
        return discussion?.isCallAvailable ?? false
    }
    
}



// MARK: - Convenience DB getters

extension PersistedMessageSystem {
    
    struct Predicate {
        enum Key: String {
            // Attributes
            case rawCategory = "rawCategory"
            case associatedData = "associatedData"
            case numberOfUnreadReceivedMessages = "numberOfUnreadReceivedMessages"
            // Relationships
            case optionalContactIdentity = "optionalContactIdentity"
            case optionalCallLogItem = "optionalCallLogItem"
            // Others
            static let callReportKind = [optionalCallLogItem.rawValue, PersistedCallLogContact.rawReportKindKey].joined(separator: ".")
        }
        static var ownedIdentityIsNotHidden: NSPredicate {
            PersistedMessage.Predicate.ownedIdentityIsNotHidden
        }
        static func withStatus(_ status: MessageStatus) -> NSPredicate {
            NSPredicate(PersistedMessage.Predicate.Key.rawStatus, EqualToInt: status.rawValue)
        }
        static func withStatusDifferentFrom(_ status: MessageStatus) -> NSPredicate {
            NSPredicate(PersistedMessage.Predicate.Key.rawStatus, DistinctFromInt: status.rawValue)
        }
        static var isNew: NSPredicate { withStatus(.new) }
        static func withinDiscussion(_ discussion: PersistedDiscussion) -> NSPredicate {
            PersistedMessage.Predicate.withinDiscussion(discussion)
        }
        static func withinDiscussion(_ discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>) -> NSPredicate {
            PersistedMessage.Predicate.withinDiscussion(discussionObjectID)
        }
        static func withCategory(_ category: Category) -> NSPredicate {
            NSPredicate(Key.rawCategory, EqualToInt: category.rawValue)
        }
        static func createdBefore(date: Date) -> NSPredicate {
            NSPredicate(PersistedMessage.Predicate.Key.timestamp, earlierThan: date)
        }
        static var isNumberOfNewMessages: NSPredicate { withCategory(.numberOfNewMessages) }
        static var isContactJoinedGroup: NSPredicate { withCategory(.contactJoinedGroup) }
        static var isContactLeftGroup: NSPredicate { withCategory(.contactLeftGroup) }
        static var isContactWasDeleted: NSPredicate { withCategory(.contactWasDeleted) }
        static var isCallMessageSystem: NSPredicate { Category.buildPredicate(with: { $0.isCallMessageSystem }) }
        static var isUpdatedDiscussionSharedSettings: NSPredicate { withCategory(.updatedDiscussionSharedSettings) }
        static var isDiscussionIsEndToEndEncrypted: NSPredicate { withCategory(.discussionIsEndToEndEncrypted) }
        static var isDiscussionWasRemotelyWiped: NSPredicate { withCategory(.discussionWasRemotelyWiped) }
        static var isDisussionUnmuted: NSPredicate {
            PersistedMessage.Predicate.isDiscussionUnmuted
        }
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
                    predicates += [NSPredicate(Key.callReportKind, EqualToInt: reportKind.rawValue)]
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
        static var hasOptionalCallLogItem: NSPredicate {
            NSPredicate(withNonNilValueForKey: Key.optionalCallLogItem)
        }
        static func hasCallReportKind(_ callReportKind: CallReportKind) -> NSPredicate {
            NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(withNonNilValueForKey: Key.optionalCallLogItem),
                NSPredicate(Key.callReportKind, EqualToInt: callReportKind.rawValue),
            ])
        }
        static func withOwnedIdentity(for ownedIdentity: PersistedObvOwnedIdentity) -> NSPredicate {
            PersistedMessage.Predicate.withOwnedIdentity(ownedIdentity)
        }
        static func withObjectID(_ objectID: NSManagedObjectID) -> NSPredicate {
            NSPredicate(withObjectID: objectID)
        }
    }
    
    
    @nonobjc static func fetchRequest() -> NSFetchRequest<PersistedMessageSystem> {
        return NSFetchRequest<PersistedMessageSystem>(entityName: PersistedMessageSystem.entityName)
    }

    
    static func getPersistedMessageSystem(discussion: PersistedDiscussion, messageId: SystemMessageIdentifier) throws -> PersistedMessageSystem? {
        guard let context = discussion.managedObjectContext else { assertionFailure(); throw ObvUICoreDataError.noContext }
        let request: NSFetchRequest<PersistedMessageSystem> = PersistedMessageSystem.fetchRequest()
        switch messageId {
        case .objectID(let objectID):
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                Predicate.withObjectID(objectID),
                Predicate.withinDiscussion(discussion),
            ])
        }
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    
    static func markAllAsNotNew(within discussion: PersistedDiscussion, dateWhenMessageTurnedNotNew: Date?) throws -> Date? {
        os_log("Call to markAllAsNotNew in PersistedMessageSystem for discussion %{public}@", log: log, type: .debug, discussion.objectID.debugDescription)
        guard let context = discussion.managedObjectContext else { return nil }
        let request: NSFetchRequest<PersistedMessageSystem> = PersistedMessageSystem.fetchRequest()
        request.includesSubentities = true
        let untilDatePredicate: NSPredicate
        if let dateWhenMessageTurnedNotNew {
            untilDatePredicate = Predicate.createdBefore(date: dateWhenMessageTurnedNotNew)
        } else {
            untilDatePredicate = NSPredicate(value: true)
        }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            untilDatePredicate,
            Predicate.withinDiscussion(discussion),
            Predicate.isNew,
        ])
        let messages = try context.fetch(request)
        guard !messages.isEmpty else { return nil }
        messages.forEach { $0.status = .read }
        return messages.map({ $0.timestamp }).max()
    }

    
    static func markAsRead(messagesWithObjectIDs: Set<NSManagedObjectID>, within discussion: PersistedDiscussion) throws {
        guard let context = discussion.managedObjectContext else { return }
        let request: NSFetchRequest<PersistedMessageSystem> = PersistedMessageSystem.fetchRequest()
        request.includesSubentities = true
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "SELF IN %@", messagesWithObjectIDs),
            Predicate.withinDiscussion(discussion),
            Predicate.withStatusDifferentFrom(.read),
        ])
        let messages = try context.fetch(request)
        messages.forEach { $0.status = .read }
    }
    
    
    public static func removeAnyNewMessagesSystemMessages(withinDiscussion discussion: PersistedDiscussion) throws {
        assert(Thread.isMainThread)
        guard let context = discussion.managedObjectContext else {
            throw ObvUICoreDataError.noContext
        }
        guard context.concurrencyType == NSManagedObjectContextConcurrencyType.mainQueueConcurrencyType else {
            assertionFailure()
            throw ObvUICoreDataError.inappropriateContext
        }
        let request: NSFetchRequest<PersistedMessageSystem> = PersistedMessageSystem.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withinDiscussion(discussion),
            Predicate.withCategory(.numberOfNewMessages),
        ])
        let messages = try context.fetch(request)
        for message in messages {
            context.delete(message)
        }
    }

    
    public static func hasRejectedIncomingCallBecauseOfDeniedRecordPermission(within context: NSManagedObjectContext) throws -> Bool {
        let request: NSFetchRequest<PersistedMessageSystem> = PersistedMessageSystem.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.isCallMessageSystem,
            Predicate.hasCallReportKind(.rejectedIncomingCallBecauseOfDeniedRecordPermission),
        ])
        request.fetchLimit = 1
        let count = try context.count(for: request)
        return count != 0
    }
    
    
    public static func getNewMessageSystemMessageObjectID(withinDiscussion discussion: PersistedDiscussion) throws -> NSManagedObjectID? {
        guard let context = discussion.managedObjectContext else { return nil }
        let request: NSFetchRequest<PersistedMessageSystem> = PersistedMessageSystem.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withinDiscussion(discussion),
            Predicate.withCategory(.numberOfNewMessages),
        ])
        request.fetchLimit = 1
        let messages = try context.fetch(request)
        return messages.first?.objectID
    }

    
    public static func countNew(within discussion: PersistedDiscussion) throws -> Int {
        guard let context = discussion.managedObjectContext else { assertionFailure(); throw ObvUICoreDataError.noContext }
        let request: NSFetchRequest<PersistedMessageSystem> = PersistedMessageSystem.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.isNew,
            Predicate.withinDiscussion(discussion),
            Predicate.isRelevantForCountingUnread,
        ])
        return try context.count(for: request)
    }
    
    
    /// Returns a dictionary where each key is the objectID of a `PersistedDiscussion` having at least one `PersistedMessageSystem` with status `.new` and which is relevant for counting "unread" messages, and the value is the number of such new messages.
    /// Note that if a discussion has no relevant message, it does *not* appear in the returned dictionary.
    ///
    /// This is used during bootstrap, to refresh the number of new messages of each discussion.
    ///
    /// See also ``static PersistedMessageReceived.getAllDiscussionsWithNewPersistedMessageReceived(ownedIdentity:)``.
    static func getAllDiscussionsWithNewAndRelevantPersistedMessageSystem(ownedIdentity: PersistedObvOwnedIdentity) throws -> [TypeSafeManagedObjectID<PersistedDiscussion>: Int] {
        
        guard let context = ownedIdentity.managedObjectContext else {
            assertionFailure()
            throw ObvUICoreDataError.noContext
        }
        
        let expressionDescription = NSExpressionDescription()
        expressionDescription.name = "numberOfNewMessages"
        expressionDescription.expression = NSExpression(forFunction: "count:", arguments: [NSExpression(forKeyPath: "rawStatus")])
        expressionDescription.expressionResultType = .integer64AttributeType

        let request = NSFetchRequest<NSFetchRequestResult>(entityName: Self.entityName)
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = [expressionDescription, PersistedMessage.Predicate.Key.discussion.rawValue]
        request.includesPendingChanges = true
        request.propertiesToGroupBy = [PersistedMessage.Predicate.Key.discussion.rawValue]
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withStatus(.new),
            Predicate.isRelevantForCountingUnread,
            Predicate.withOwnedIdentity(for: ownedIdentity),
        ])

        let results = try context.fetch(request) as? [[String: AnyObject]] ?? []

        var numberOfNewMessageForDiscussionWithObjectID = [TypeSafeManagedObjectID<PersistedDiscussion>: Int]()
        for result in results {
            guard let discussionObjectID = result["discussion"] as? NSManagedObjectID else { assertionFailure(); continue}
            guard let numberOfNewMessages = result["numberOfNewMessages"] as? Int else { assertionFailure(); continue}
            numberOfNewMessageForDiscussionWithObjectID[TypeSafeManagedObjectID<PersistedDiscussion>(objectID: discussionObjectID)] = numberOfNewMessages
        }
        
        return numberOfNewMessageForDiscussionWithObjectID
        
    }

    
    
    public static func countNewForAllNonHiddenOwnedIdentities(within context: NSManagedObjectContext) throws -> Int {
        let request: NSFetchRequest<PersistedMessageSystem> = PersistedMessageSystem.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.isNew,
            Predicate.isDisussionUnmuted,
            Predicate.isRelevantForCountingUnread,
            Predicate.ownedIdentityIsNotHidden,
        ])
        return try context.count(for: request)
    }

    
    public static func getFirstNewRelevantSystemMessage(in discussion: PersistedDiscussion) throws -> PersistedMessageSystem? {
        guard let context = discussion.managedObjectContext else { assertionFailure(); throw ObvUICoreDataError.noContext }
        let request: NSFetchRequest<PersistedMessageSystem> = PersistedMessageSystem.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: PersistedMessage.Predicate.Key.sortIndex.rawValue, ascending: true)]
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.isNew,
            Predicate.withinDiscussion(discussion),
            Predicate.isRelevantForCountingUnread,
        ])
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
    
    
    public static func countNewRelevantSystemMessages(in discussion: PersistedDiscussion) throws -> Int {
        guard let context = discussion.managedObjectContext else { assertionFailure(); throw ObvUICoreDataError.noContext }
        let request: NSFetchRequest<PersistedMessageSystem> = PersistedMessageSystem.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.isNew,
            Predicate.withinDiscussion(discussion),
            Predicate.isRelevantForCountingUnread,
        ])
        return try context.count(for: request)
    }
    
    
    public static func getAllNewRelevantSystemMessages(in discussion: PersistedDiscussion) throws -> [PersistedMessageSystem] {
        guard let context = discussion.managedObjectContext else { assertionFailure(); throw ObvUICoreDataError.noContext }
        let request: NSFetchRequest<PersistedMessageSystem> = PersistedMessageSystem.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.isNew,
            Predicate.withinDiscussion(discussion),
            Predicate.isRelevantForCountingUnread,
        ])
        return try context.fetch(request)
    }

    
    public static func getNumberOfNewMessagesSystemMessage(in discussion: PersistedDiscussion) throws -> PersistedMessageSystem? {
        guard let context = discussion.managedObjectContext else { assertionFailure(); throw ObvUICoreDataError.noContext }
        let request: NSFetchRequest<PersistedMessageSystem> = PersistedMessageSystem.fetchRequest()
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            Predicate.withinDiscussion(discussion),
            Predicate.isNumberOfNewMessages,
        ])
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
    
}


// MARK: - Sending notifications on change

extension PersistedMessageSystem {
    
    public override func prepareForDeletion() {
        super.prepareForDeletion()
        guard let managedObjectContext else { assertionFailure(); return }
        guard managedObjectContext.concurrencyType != .mainQueueConcurrencyType else { return }
        guard let discussionObjectID = discussion?.typedObjectID else { return }
        userInfoForDeletion = ["objectID": objectID,
                               "discussionObjectID": discussionObjectID]
    }
   
    public override func didSave() {
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

public extension TypeSafeManagedObjectID where T == PersistedMessageSystem {
    var downcast: TypeSafeManagedObjectID<PersistedMessage> {
        TypeSafeManagedObjectID<PersistedMessage>(objectID: objectID)
    }
}
