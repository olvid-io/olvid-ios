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
import ObvTypes


public enum ObvUICoreDataError: Error {
    
    case unhandledCallReportKind
    case callReportKindIsNil
    case obvDialogIsNil
    case inconsistentOneToOneDiscussionIdentifier // ok
    case cannotInsertMessageInOneToOneDiscussionFromNonOneToOneContact
    case couldNotFindDiscussion
    case couldNotFindDiscussionWithId(discussionId: DiscussionIdentifier)
    case couldNotFindOwnedIdentity
    case couldNotFindGroupV1InDatabase(groupIdentifier: GroupV1Identifier)
    case couldNotFindGroupV2InDatabase(groupIdentifier: GroupV2Identifier)
    case couldNotDetemineGroupV1
    case couldNotDetemineGroupV2
    case couldNotFindPersistedMessage
    case couldNotFindPersistedMessageReceived
    case couldNotFindPersistedMessageSent
    case noContext
    case inappropriateContext
    case unexpectedFromContactIdentity
    case cannotUpdateConfigurationOfOneToOneDiscussionFromNonOneToOneContact
    case atLeastOneOfOneToOneIdentifierAndGroupIdentifierIsExpectedToBeNil
    case contactNeitherGroupOwnerNorPartOfGroupMembers
    case contactIsNotPartOfTheGroup(groupIdentifier: GroupV2Identifier, contactIdentifier: ObvContactIdentifier)
    case unexpectedOwnedCryptoId
    case ownedDeviceNotFound
    case couldNotDetermineTheOneToOneDiscussion
    case couldNotFindOneToOneContactWithId(contactIdentifier: ObvContactIdentifier)
    case couldNotFindContactWithId(contactIdentifier: ObvContactIdentifier)
    case couldNotFindDraft
    case couldNotDetermineContactCryptoId
    case tryingToUpdateAnOwnedIdentityWithTheDataOfAnotherOwnedIdentity // ok
    case passwordIsTooShortToHideProfile
    case anotherPasswordIsThePrefixOfThisPassword
    case couldNotCastFetchedResult
    case couldNotGetSumOfBadgeCounts
    case couldNotDeterminePersistedObvOwnedIdentityPermanentID
    case couldNotDeterminePersistedObvContactIdentityPermanentID
    case couldNotSavePhoto
    case theFullDisplayNameOfTheContactIsEmpty
    case couldNotLockOneToOneDiscussion
    case contactsOwnedIdentityRelationshipIsNil
    case personNameComponentsIsNil
    case unexpectedContactIdentifier
    case cannotDeleteDiscussionFromAllOwnedDevicesAsOwnedIdentityHasNoOtherReachableDevice
    case cannotDeleteOneToOneDiscussionFromContactDevices
    case persistedGroupV2AlreadyExists
    case couldNotExtractJPEGData
    case ownedIdentityIsNotPartOfThisGroup
    case theInitiatorIsNotPartOfTheGroup
    case theInitiatorIsNotAllowedToChangeSettings
    case theOwnedIdentityIsNoAllowedToChangeSettings
    case couldNotGetTrustedGroupDetails
    case ownedIdentityIsNil
    case unexpectedOwnedDeviceIdentifier
    case unexpectedContactDeviceIdentifier
    case couldNotParseContactDeviceUID
    case unexpectedDiscussionForMessage
    case couldNotConstructMessageReferenceJSON
    case couldNotDetermineDiscussionIdentifier
    case cannotChangeShareConfigurationOfLockedDiscussion
    case cannotChangeShareConfigurationOfPreDiscussion
    case aContactCannotWipeMessageFromLockedDiscussion
    case aContactCannotWipeMessageFromPrediscussion
    case aContactCannotDeleteAllMessagesWithinLockedDiscussion
    case aContactCannotDeleteAllMessagesWithinPreDiscussion
    case ownedIdentityCannotGloballyDeletePrediscussion
    case unexpectedOwnedIdentity
    case ownedIdentityDoesNotHaveAnotherReachableDevice
    case cannotGloballyDeleteMessageFromLockedOrPrediscussion
    case cannotGloballyDeleteLockedOrPrediscussion
    case aMessageCannotBeUpdatedInLockedDiscussion
    case aMessageCannotBeUpdatedInPrediscussion
    case aContactRequestedUpdateOnMessageFromSomeoneElse
    case contactIdentityIsNil
    case groupV1IsNil
    case groupV2IsNil
    case unexpectedMessageKind
    case discussionIsNotLocked
    case cannotDeleteMessageFromAllOwnedDevicesAsOwnedIdentityHasNoOtherReachableDevice
    case onlySentMessagesCanBeDeletedFromContactDevicesWhenInGroupV1Discussion
    case onlySentMessagesCanBeDeletedFromContactDevicesWhenInOneToOneDiscussion
    case cannotDeleteGroupV1DiscussionFromContactDevices
    case unknownDiscussionType
    case newTitleIsEmpty
    case unexpectedDiscussionKind
    case couldNotDetermineGroupOwner
    case couldNotExtractRequiredAttributes
    case couldNotExtractRequiredRelationships
    case unexpectedContact
    case inconsistentOneToOneIdentifier
    case unexpectedObvDialogCategory
    case unexpectedPersistedMessageKind
    case inconsistentDiscussion
    case invalidSenderSequenceNumber
    case couldNotAddTimestampedMetadata
    case couldNotDeterminePersistedMessagePermanentID
    case inappropriateInitilizerCalled
    case tryingToCreateEmptyPersistedMessageReceived
    case cannotCreatePersistedMessageReceivedAsDiscussionIsNotActive
    case cannotCreatePersistedMessageSentAsDiscussionIsNotActive
    case otherGroupV1MembersDoesNotContainContactWhoSentMessage
    case otherGroupV2MembersDoesNotContainContactWhoSentMessage
    case groupV2MessageReceivedFromMemberNotAllowedToSendMessages
    case invalidMessageIdentifierFromEngine
    case theTextBodyOfThisPersistedMessageSentCannotBeEditedNow
    case theRequesterIsNotTheOwnedIdentityWhoCreatedThePersistedMessageSent
    case ownedIdentityIsAllowedToSendMessagesInThisDiscussion
    case contactIdentityIsNotActive
    case recipientInfosIsEmpty
    case persistedMessageSentAlreadyExists
    case tryingToResetGroupNameWithEmptyString
    case unexpectedGroupUID
    case unexpectedGroupOwner
    case initiatorOfTheChangeIsNotTheGroupOwner
    case unexpecterCountOfOwnedIdentities
    case unexpectedGroupType
    case couldNotFindPersistedDraftFyleJoin
    case couldNotDetermineOneToOneDiscussionIdentifier
    case aPersistedCallLogItemWithTheSameUUIDAlreadyExists
    case couldNotDetermineOwnedCryptoId
    case couldNotFindPersistedMessageExpiration
    case invalidEmoji
    case cannotCreateReceivedFyleMessageJoinWithStatusForWipedMessage
    case theFyleShouldHaveBeenCreatedByTheSuperclassInitializer
    case callMustBePerformedOnMainThread
    case couldNotFindFyle
    case couldNotFindReceivedFyleMessageJoinWithStatus
    case fyleIsNil
    case cannotCreateSentFyleMessageJoinWithStatusForWipedMessage
    case couldNotFindPersistedObvContactIdentityAlthoughMemberIsNotPending
    case tryingToUpdateMemberWithPersistedContactThatDoesNotHaveAppropriateIdentity
    case tryingToUpdateMemberWithPersistedContactThatDoesNotHaveAppropriateAssociatedOwnedIdentity
    case couldNotGetAddedMemberCryptoId
    case noMessageIdentifierForThisMessageType
    case discussionIsNil
    case unexpectedAttachmentNumber
    case stringParsingFailed
    case thisSpecificSystemMessageCannotBeDeleted
    case cannotGloballyDeleteSystemMessage
    case cannotGloballyDeleteWipedMessage
    case wipeRequestedByNonGroupMember
    case wipeRequestedByMemberNotAllowedToRemoteDelete
    case persistedGroupV2DiscussionIsNil
    case deleteRequestMakesNoSenseAsGroupHasNoOtherMembers
    case ownedIdentityIsNotAllowedToDeleteThisMessage
    case messageReceivedByMemberNotAllowedToSendMessage
    case ownedIdentityIsNotAllowedToSendMessages
    case updateRequestReceivedByMemberNotAllowedToToEditOrRemoteDeleteOwnMessages
    case ownedIdentityIsNotAllowedToEditOrRemoteDeleteOwnMessages
    case requestToDeleteAllMessagesWithinThisGroupDiscussionFromContactNotAllowedToDoSo
    case ownedIdentityIsNotAllowedToDeleteDiscussion
    case couldNotParseGroupIdentifier
    case couldNotFindSourceFile
    case couldNotComputeSHA256
    case sha256OfReceivedFileReferenceByObvAttachmentDoesNotMatchWhatWeExpect
    case mentionIsOutOfBounds
    case cannotDetermineTextBodyContainingTheMention
    case messageHasNoBodyAndThusCannotContainMention
    case persistedMessageReceivedAlreadyExist
    case couldNotDetermineMessageReferenceFromPersistedMessage
    case couldNotDetermineRequestType
    case couldNotDetermineRequester
    case unexpectedIdentifiers
    case couldNotFindSerializedMessageJSON
    case stringEncodingFailed
    case noDiscussionWasSpecified
    case doesNotReferenceReceivedMessage
    case cannotReactToSystemMessage
    case contactsCannotDeleteAllMessagesOfThisKindOfDiscussion
    case messageHasNoBody
    case unexpectedObvMessageSource
    case messageIsPriorToLastRemoteDeletionRequest
    case cannotCreateReceivedMessageThatAlreadyExpired
    case locationIsAssociatedToAWrongTypeOfMessage
    case cannotCreateOrUpdateLocation
    case locationOfTypeSendShouldNotBeUpdated
    case messageIsNotAssociatedToThisLocation
    case contactDeviceNotFound
    case unexpectedNilValue(valueName: String)
    case unexpectedLocationType
    case cannotSendWipedMessage
    case couldNotTurnPersistedMessageSentIntoAMessageJSON

    public var errorDescription: String? {
        switch self {
        case .couldNotTurnPersistedMessageSentIntoAMessageJSON:
            return "Could not turn PersistedMessageSent into a MessageJSON"
        case .cannotSendWipedMessage:
            return "Cannot send wiped message"
        case .unexpectedLocationType:
            return "Unexpected location type"
        case .unexpectedNilValue(valueName: let valueName):
            return "Unexpected nil value \(valueName)"
        case .contactDeviceNotFound:
            return "Contact device not found"
        case .cannotCreateReceivedMessageThatAlreadyExpired:
            return "Cannot create received message that already expired"
        case .messageIsPriorToLastRemoteDeletionRequest:
            return "Message is prior to last remote deletion request"
        case .unhandledCallReportKind:
            return "Unhandled call report kind"
        case .callReportKindIsNil:
            return "Call report kind is nil"
        case .obvDialogIsNil:
            return "ObvDialog is nil"
        case .unexpectedObvMessageSource:
            return "Unexpected ObvMessageSource"
        case .messageHasNoBody:
            return "Message has no body"
        case .cannotReactToSystemMessage:
            return "Cannot react to system message"
        case .doesNotReferenceReceivedMessage:
            return "Does not reference received message"
        case .noDiscussionWasSpecified:
            return "No discussion was specified"
        case .stringEncodingFailed:
            return "String encoding failed"
        case .couldNotFindSerializedMessageJSON:
            return "Could not find serialized message JSON"
        case .unexpectedIdentifiers:
            return "Unexpected identifiers"
        case .couldNotDetermineRequester:
            return "Could not determine requester"
        case .couldNotDetermineRequestType:
            return "Could not determine request type"
        case .couldNotDetermineMessageReferenceFromPersistedMessage:
            return "Could not determine message reference from persisted message"
        case .persistedMessageReceivedAlreadyExist:
            return "PersistedMessageReceived already exists"
        case .messageHasNoBodyAndThusCannotContainMention:
            return "Message has no body and thus cannot contain a mention"
        case .cannotDetermineTextBodyContainingTheMention:
            return "Cannot determine the text body containing the mention"
        case .mentionIsOutOfBounds:
            return "Mention is out of bounds"
        case .sha256OfReceivedFileReferenceByObvAttachmentDoesNotMatchWhatWeExpect:
            return "SHA-256 of received file referenced by ObvAttachment does not match what we expect"
        case .couldNotComputeSHA256:
            return "Could not compute SHA-256"
        case .couldNotFindSourceFile:
            return "Could not find source file"
        case .couldNotParseGroupIdentifier:
            return "Could not parse group identifier"
        case .ownedIdentityIsNotAllowedToDeleteDiscussion:
            return "Owned identity is not allowed to delete discussion"
        case .requestToDeleteAllMessagesWithinThisGroupDiscussionFromContactNotAllowedToDoSo:
            return "Request to delete all messages within this group discussion from contact not allowed to do so"
        case .ownedIdentityIsNotAllowedToEditOrRemoteDeleteOwnMessages:
            return "Owned identity is not allowed to edit or remote-delete own message"
        case .updateRequestReceivedByMemberNotAllowedToToEditOrRemoteDeleteOwnMessages:
            return "Update request received by member not allowed to edit or remote-delete own messages"
        case .ownedIdentityIsNotAllowedToSendMessages:
            return "Owned identity is not allowed to send messages"
        case .messageReceivedByMemberNotAllowedToSendMessage:
            return "Message received by member not allowed to send message"
        case .ownedIdentityIsNotAllowedToDeleteThisMessage:
            return "The owned identity is not allowed to delete this message"
        case .deleteRequestMakesNoSenseAsGroupHasNoOtherMembers:
            return "Delete request makes no sense as group has no other members"
        case .persistedGroupV2DiscussionIsNil:
            return "Persisted group v2 discussion is nil"
        case .wipeRequestedByMemberNotAllowedToRemoteDelete:
            return "Wip requested by member not allowed to delete"
        case .wipeRequestedByNonGroupMember:
            return "Wipe requested by non group member"
        case .cannotGloballyDeleteWipedMessage:
            return "Cannot globally wipe system message"
        case .cannotGloballyDeleteSystemMessage:
            return "Cannot globally delete system message"
        case .thisSpecificSystemMessageCannotBeDeleted:
            return "This specific system message cannot be deleted"
        case .stringParsingFailed:
            return "String parsing failed"
        case .unexpectedAttachmentNumber:
            return "Unexpected attachment number"
        case .discussionIsNil:
            return "Discussion is nil"
        case .noMessageIdentifierForThisMessageType:
            return "No message identifier for this message type"
        case .couldNotGetAddedMemberCryptoId:
            return "Could not get added member crypto Id"
        case .tryingToUpdateMemberWithPersistedContactThatDoesNotHaveAppropriateAssociatedOwnedIdentity:
            return "Trying to update member with a contact that does not have the appropriate associted owned identity"
        case .tryingToUpdateMemberWithPersistedContactThatDoesNotHaveAppropriateIdentity:
            return "Trying to update member with a contact that does not have the appropriate identity"
        case .couldNotFindPersistedObvContactIdentityAlthoughMemberIsNotPending:
            return "Could not find PersistedObvContactIdentity although the member is not pending"
        case .cannotCreateSentFyleMessageJoinWithStatusForWipedMessage:
            return "Cannot create SentFyleMessageJoinWithStatus for wiped message"
        case .fyleIsNil:
            return "Fyle is nil"
        case .couldNotFindReceivedFyleMessageJoinWithStatus:
            return "Could not find ReceivedFyleMessageJoinWithStatus"
        case .couldNotFindFyle:
            return "Could not find Fyle"
        case .callMustBePerformedOnMainThread:
            return "Call must be performed on the main thread"
        case .theFyleShouldHaveBeenCreatedByTheSuperclassInitializer:
            return "The Fyle should have been created by the superclass initializer"
        case .cannotCreateReceivedFyleMessageJoinWithStatusForWipedMessage:
            return "Cannot create ReceivedFyleMessageJoinWithStatus for wiped message"
        case .invalidEmoji:
            return "Invalid emoji"
        case .couldNotFindPersistedMessageExpiration:
            return "Could not find PersistedMessageExpiration"
        case .couldNotDetermineOwnedCryptoId:
            return "Could not determine owned crypto id"
        case .aPersistedCallLogItemWithTheSameUUIDAlreadyExists:
            return "A PersistedCallLogItem with the same UUID already exists"
        case .couldNotDetermineOneToOneDiscussionIdentifier:
            return "Could not determine one-to-one discussion's identifer"
        case .couldNotFindPersistedDraftFyleJoin:
            return "Could not find PersistedDraftFyleJoin"
        case .unexpectedGroupType:
            return "Unexpected group type"
        case .unexpecterCountOfOwnedIdentities:
            return "Unexpected count of owned identities"
        case .initiatorOfTheChangeIsNotTheGroupOwner:
            return "Initiator of the change is not the group owner"
        case .unexpectedGroupOwner:
            return "Unexpected group owner"
        case .unexpectedGroupUID:
            return "Unexpected group UID"
        case .tryingToResetGroupNameWithEmptyString:
            return "Trying to reset group name with an empty string"
        case .persistedMessageSentAlreadyExists:
            return "PersistedMessageSent already exists"
        case .recipientInfosIsEmpty:
            return "Recipient infos is empty"
        case .contactIdentityIsNotActive:
            return "Contact identity is not active"
        case .ownedIdentityIsAllowedToSendMessagesInThisDiscussion:
            return "Owned identity is not allowed to send messages in this discussion"
        case .cannotCreatePersistedMessageSentAsDiscussionIsNotActive:
            return "Cannot create PersistedMessageSent as discussion is not active"
        case .theRequesterIsNotTheOwnedIdentityWhoCreatedThePersistedMessageSent:
            return "The requested is not the owned identity who created the PersistedMessageSent"
        case .theTextBodyOfThisPersistedMessageSentCannotBeEditedNow:
            return "The text body of this PersistedMessageSent cannot be edited for now"
        case .invalidMessageIdentifierFromEngine:
            return "Invalid message identifier from engine"
        case .groupV2MessageReceivedFromMemberNotAllowedToSendMessages:
            return "Group v2 message received from member who is not allowed to send messages"
        case .otherGroupV1MembersDoesNotContainContactWhoSentMessage:
            return "Other group v1 members does not contain contact who sent the message"
        case .otherGroupV2MembersDoesNotContainContactWhoSentMessage:
            return "Other group v2 members does not contain contact who sent the message"
        case .cannotCreatePersistedMessageReceivedAsDiscussionIsNotActive:
            return "Cannot create PersistedMessageReceived as the discussion is not active"
        case .tryingToCreateEmptyPersistedMessageReceived:
            return "Trying to create an empty PersistedMessageReceived"
        case .inappropriateInitilizerCalled:
            return "Inappropriate initializer called"
        case .couldNotDeterminePersistedMessagePermanentID:
            return "Could not determine the permanent ID of a PersistedMessage"
        case .couldNotAddTimestampedMetadata:
            return "Could not add timestamped metadata"
        case .invalidSenderSequenceNumber:
            return "Invalid sender sequence number"
        case .inconsistentDiscussion:
            return "Inconsistent discussion"
        case .unexpectedPersistedMessageKind:
            return "Unexpected PersistedMessage kind"
        case .unexpectedObvDialogCategory:
            return "Unexpected ObvDialog category"
        case .inconsistentOneToOneIdentifier:
            return "Inconsistent one-to-one identifier"
        case .cannotDeleteOneToOneDiscussionFromContactDevices:
            return "Cannot delete one-to-one discussion from contact devices"
        case .couldNotExtractRequiredRelationships:
            return "Could not extract required relationships"
        case .couldNotExtractRequiredAttributes:
            return "Could not extract required attributes"
        case .couldNotDetermineGroupOwner:
            return "Could not determine group owner"
        case .unexpectedDiscussionKind:
            return "Unexpected discussion kind"
        case .newTitleIsEmpty:
            return "New title is empty"
        case .unknownDiscussionType:
            return "Unknown discussion type"
        case .cannotDeleteGroupV1DiscussionFromContactDevices:
            return "Cannot delete group v1 discussion from contact devices"
        case .onlySentMessagesCanBeDeletedFromContactDevicesWhenInGroupV1Discussion:
            return "Only sent messages can be deleted from contact devices when in group v1 discussion"
        case .onlySentMessagesCanBeDeletedFromContactDevicesWhenInOneToOneDiscussion:
            return "Only sent messages can be deleted from contact devices when in one-to-one discussion"
        case .cannotDeleteMessageFromAllOwnedDevicesAsOwnedIdentityHasNoOtherReachableDevice:
            return "Cannot delete message from all owned devices as owned identity has no other reachable device"
        case .discussionIsNotLocked:
            return "Discussion is not locked"
        case .unexpectedMessageKind:
            return "Unexpected message kind"
        case .groupV2IsNil:
            return "Group V2 is nil"
        case .groupV1IsNil:
            return "Group V1 is nil"
        case .contactIdentityIsNil:
            return "Contact identitity is nil"
        case .aContactRequestedUpdateOnMessageFromSomeoneElse:
            return "A contact requested update on message from someone else"
        case .aMessageCannotBeUpdatedInPrediscussion:
            return "A message cannot be updated in pre-discussion"
        case .aMessageCannotBeUpdatedInLockedDiscussion:
            return "A message cannot be updated in locked discussion"
        case .cannotGloballyDeleteLockedOrPrediscussion:
            return "Cannot globally delete locked or pre-discussion"
        case .cannotGloballyDeleteMessageFromLockedOrPrediscussion:
            return "Cannot globally delete message from locked or pre-discussion"
        case .ownedIdentityDoesNotHaveAnotherReachableDevice:
            return "Owned identity does not have another reachable device"
        case .unexpectedOwnedIdentity:
            return "Unexpected owned identity"
        case .ownedIdentityCannotGloballyDeletePrediscussion:
            return "Owned identity cannot globally delete pre-discussion"
        case .aContactCannotDeleteAllMessagesWithinPreDiscussion:
            return "A contact cannot delete all messages from a pre-discussion"
        case .aContactCannotDeleteAllMessagesWithinLockedDiscussion:
            return "A contact cannot delete all messages from a locked discussion"
        case .aContactCannotWipeMessageFromPrediscussion:
            return "A contact cannot wipe a message from a pre-discussion"
        case .aContactCannotWipeMessageFromLockedDiscussion:
            return "A contact cannot wipe a message from a locked discussion"
        case .cannotChangeShareConfigurationOfLockedDiscussion:
            return "Cannot change share configuration of locked discussion"
        case .couldNotDetermineDiscussionIdentifier:
            return "Could not determine discussion identifier"
        case .couldNotConstructMessageReferenceJSON:
            return "Could not construct message MessageReferenceJSON"
        case .couldNotParseContactDeviceUID:
            return "Could not parse contact device UID"
        case .unexpectedContactDeviceIdentifier:
            return "Unexpected contact device identifier"
        case .unexpectedOwnedDeviceIdentifier:
            return "Unexpected owned device identifier"
        case .ownedIdentityIsNil:
            return "Owned identity is nil"
        case .couldNotGetTrustedGroupDetails:
            return "Could not get trusted group details"
        case .theOwnedIdentityIsNoAllowedToChangeSettings:
            return "The owned identity is not allowed to change settings"
        case .theInitiatorIsNotAllowedToChangeSettings:
            return "The initiator is not allowed to change settings"
        case .theInitiatorIsNotPartOfTheGroup:
            return "The initiator is not part of the group"
        case .ownedIdentityIsNotPartOfThisGroup:
            return "Owned identity is not part of this group"
        case .couldNotExtractJPEGData:
            return "Could not extract JPEG data"
        case .persistedGroupV2AlreadyExists:
            return "PersistedGroupV2 already exists"
        case .cannotDeleteDiscussionFromAllOwnedDevicesAsOwnedIdentityHasNoOtherReachableDevice:
            return "Cannot delete discussion from all owned devices as the owned identity has no other reachable device"
        case .unexpectedContactIdentifier:
            return  "Unexpected contact identifier"
        case .personNameComponentsIsNil:
            return "Person name components is nil"
        case .contactsOwnedIdentityRelationshipIsNil:
            return "The contact's owned identity relationship is nil"
        case .couldNotLockOneToOneDiscussion:
            return "Could not lock the persisted oneToOne discussion"
        case .theFullDisplayNameOfTheContactIsEmpty:
            return "The full display name of the contact is empty"
        case .couldNotSavePhoto:
            return "Could not save photo"
        case .couldNotDeterminePersistedObvOwnedIdentityPermanentID:
            return "Could not determine the permanent ID of a PersistedObvOwnedIdentity"
        case .couldNotDeterminePersistedObvContactIdentityPermanentID:
            return "Could not determine the permanent ID of a PersistedObvContactIdentity"
        case .couldNotGetSumOfBadgeCounts:
            return "Could not get sumOfBadgeCounts"
        case .couldNotCastFetchedResult:
            return "Could cast fetched result"
        case .anotherPasswordIsThePrefixOfThisPassword:
            return "Another password is the prefix of this password"
        case .passwordIsTooShortToHideProfile:
            return "Password is too short to hide profile"
        case .tryingToUpdateAnOwnedIdentityWithTheDataOfAnotherOwnedIdentity:
            return "Trying to update an owned identity with the data of another owned identity"
        case .couldNotDetemineGroupV1:
            return "Could not determine group V1"
        case .couldNotDetemineGroupV2:
            return "Could not determine group V2"
        case .inconsistentOneToOneDiscussionIdentifier:
            return "Inconsistent OneToOne discussion identifier"
        case .cannotInsertMessageInOneToOneDiscussionFromNonOneToOneContact:
            return "Cannot insert a message in a OneToOne discussion from a contact that is not OneToOne"
        case .couldNotFindDiscussion:
            return "Could not find discussion"
        case .couldNotFindDiscussionWithId:
            return "Could not find discussion given for the identifier"
        case .couldNotFindOwnedIdentity:
            return "Could not find the owned identity corresponding to this contact"
        case .couldNotFindGroupV1InDatabase:
            return "Could not find group V1 in database"
        case .couldNotFindGroupV2InDatabase:
            return "Could not find group V2 in database"
        case .noContext:
            return "No context available"
        case .couldNotFindPersistedMessageReceived:
            return "Could not find PersistedMessageReceived"
        case .unexpectedFromContactIdentity:
            return "UnexpectedFromContactIdentity"
        case .cannotUpdateConfigurationOfOneToOneDiscussionFromNonOneToOneContact:
            return "Cannot update OneToOne discussion shared settings sent by a contact that is not OneToOne"
        case .atLeastOneOfOneToOneIdentifierAndGroupIdentifierIsExpectedToBeNil:
            return "We expect at least one of OneOfOneToOneIdentifier and GroupIdentifier to be nil"
        case .contactNeitherGroupOwnerNorPartOfGroupMembers:
            return "This contact is not the group owner nor part of the group members"
        case .contactIsNotPartOfTheGroup:
            return "The contact is not part of the group"
        case .inappropriateContext:
            return "Inappropriate context"
        case .unexpectedOwnedCryptoId:
            return "Unexpected owned cryptoId"
        case .ownedDeviceNotFound:
            return "Owned device not found"
        case .couldNotDetermineTheOneToOneDiscussion:
            return "Could not determine the OneToOne discussion"
        case .couldNotFindPersistedMessageSent:
            return "Could not find persisted message sent"
        case .couldNotFindPersistedMessage:
            return "Could not find persisted message"
        case .couldNotFindOneToOneContactWithId(contactIdentifier: _):
            return "Could not find one2one contact"
        case .couldNotFindContactWithId:
            return "Could not find contact with Id"
        case .couldNotFindDraft:
            return "Could not find draft"
        case .couldNotDetermineContactCryptoId:
            return "Could not determine contact crypto id"
        case .unexpectedDiscussionForMessage:
            return "Unexpected discussion for message"
        case .cannotChangeShareConfigurationOfPreDiscussion:
            return "Cannot change shared configurtion of Pre-discussion"
        case .unexpectedContact:
            return "Unexpected contact"
        case .contactsCannotDeleteAllMessagesOfThisKindOfDiscussion:
            return "Contacts cannot delete all messages of this kind of discussion"
        case .locationIsAssociatedToAWrongTypeOfMessage:
            return "location is associated to the wrong type of message (should be Sent or Received)"
        case .cannotCreateOrUpdateLocation:
            return "cannot create or update location"
        case .locationOfTypeSendShouldNotBeUpdated:
            return "location of type Send should not be updated"
        case .messageIsNotAssociatedToThisLocation:
            return "message is not associated to this location"
        }
    }

}
