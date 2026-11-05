/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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
import Intents
import ObvTypes
import ObvDesignSystem
import ObvSystemIcon
import ObvUICoreDataStructs
import OlvidUtils


/// This class is in charge of mapping Communication Information into Intent framework objects.
final class ObvCommunicationMapper {
    
    static func interaction(communicationType: ObvCommunicationType) throws -> INInteraction {
        
        // Create the INIntent
        
        let intent: INIntent
        
        switch communicationType {
            
        case .incomingMessage(contact: let contact, discussionKind: let discussionKind, messageRepliedTo: let messageRepliedTo, mentions: let mentions):
            let messageOrReaction: MessageOrReactionMetadata = .message(discussionKind: discussionKind, mentions: mentions, messageRepliedTo: messageRepliedTo)
            intent = try Self.incomingMessageOrReaction(contact: contact, messageOrReaction: messageOrReaction)
            
        case .incomingReaction(reactor: let reactor, sentMessageReactedTo: let sentMessageReactedTo):
            let messageOrReaction: MessageOrReactionMetadata = .reaction(sentMessageReactedTo: sentMessageReactedTo)
            intent = try Self.incomingMessageOrReaction(contact: reactor, messageOrReaction: messageOrReaction)
            
        case .incomingPollVote(reactor: let reactor, sentMessageVotedTo: let sentMessageVotedTo):
            let messageOrReaction: MessageOrReactionMetadata = .vote(sentMessageVotedTo: sentMessageVotedTo)
            intent = try Self.incomingMessageOrReaction(contact: reactor, messageOrReaction: messageOrReaction)
            
        case .outgoingMessage(sentMessage: let sentMessage):
            intent = Self.outgoingMessage(sentMessage: sentMessage)
            
        case .callLog(callLog: let callLog):
            intent = try Self.callLog(callLog: callLog)
            
        }
        
        // Use the INIntent to create the INInteraction, and update it
        // The `groupIdentifier` of the INInteraction makes it possible to delete the interactions when required.
        
        let interaction = INInteraction(intent: intent, response: nil)

        switch communicationType {
            
        case .incomingMessage(contact: _, discussionKind: let discussionKind, messageRepliedTo: _, mentions: _):
            
            interaction.direction = .incoming
            interaction.groupIdentifier = discussionKind.discussionIdentifier.description
            
        case .incomingReaction(reactor: _, sentMessageReactedTo: let sentMessageReactedTo):
            
            interaction.direction = .incoming
            interaction.groupIdentifier = sentMessageReactedTo.discussionKind.discussionIdentifier.description

        case .incomingPollVote(reactor: _, sentMessageVotedTo: let sentMessageVotedTo):
            
            interaction.direction = .incoming
            interaction.groupIdentifier = sentMessageVotedTo.discussionKind.discussionIdentifier.description

            
        case .outgoingMessage(sentMessage: let sentMessage):
            
            interaction.direction = .outgoing
            interaction.groupIdentifier = sentMessage.discussionKind.discussionIdentifier.description
            
        case .callLog(callLog: let callLog):

            switch callLog.direction {
            case .incoming:
                interaction.direction = .incoming
            case .outgoing:
                interaction.direction = .outgoing
            }
            interaction.groupIdentifier = callLog.discussionKind.discussionIdentifier.description

        }
        
        // Return the INInteraction
        
        return interaction
        
    }
    
    
    // MARK: - Outgoing call
    
    private static func callLog(callLog: PersistedCallLogItemStructure) throws -> INStartCallIntent {
                
        let contacts = callLog.otherParticipants.map({ $0.contactIdentity.toINPerson(withINImage: true) })
        
        let caller: INPerson
        switch callLog.direction {
        case .incoming:
            guard let _caller = callLog.otherParticipants.first(where: { $0.isCaller }).map({ $0.contactIdentity })?.toINPerson(withINImage: true) else {
                assertionFailure()
                throw ObvError.couldNotDetermineCallerOfIncomingCall
            }
            caller = _caller
        case .outgoing:
            caller = callLog.discussionKind.ownedIdentity.toINPerson(withINImage: true)
        }
        
        let callRecordType: INCallRecordType
        switch callLog.callReportKind {
        case .rejectedOutgoingCall:
            callRecordType = .outgoing
        case .acceptedOutgoingCall:
            callRecordType = .outgoing
        case .uncompletedOutgoingCall:
            callRecordType = .outgoing
        case .acceptedIncomingCall:
            callRecordType = .inProgress
        case .missedIncomingCall:
            callRecordType = .missed
        case .rejectedIncomingCall:
            callRecordType = .missed
        case .filteredIncomingCall:
            callRecordType = .missed
        case .rejectedIncomingCallBecauseOfDeniedRecordPermission:
            callRecordType = .missed
        }
        
        let callRecordToCallBack = INCallRecord(identifier: callLog.callUUID.uuidString,
                                                dateCreated: Date.now,
                                                caller: caller,
                                                callRecordType: callRecordType,
                                                callCapability: .audioCall,
                                                callDuration: nil,
                                                unseen: nil,
                                                numberOfCalls: nil)
        
        let intent = INStartCallIntent(callRecordFilter: nil,
                                       callRecordToCallBack: callRecordToCallBack,
                                       audioRoute: .speakerphoneAudioRoute,
                                       destinationType: .normal,
                                       contacts: contacts,
                                       callCapability: .audioCall)

        return intent

    }
    
    
    // MARK: - Outgoing message or reaction
    
    
    private static func outgoingMessage(sentMessage: PersistedMessageSentStructure) -> INSendMessageIntent {
        
        let discussionKind = sentMessage.discussionKind
        
        let sender = discussionKind.ownedIdentity.toINPerson(withINImage: true)
        
        let recipients: [INPerson]
        switch discussionKind {
        case .oneToOneDiscussion(let structure):
            recipients = [structure.contactIdentity.toINPerson(withINImage: true)]
        case .groupDiscussion(let structure):
            // Include the owned identity so that self-groups (0 contacts) produce a non-empty
            // recipients list, which Siri requires to suggest the conversation in share sheets.
            recipients = structure.contactGroup.contactIdentities.map({ $0.toINPerson(withINImage: false) })
                       + [discussionKind.ownedIdentity.toINPerson(withINImage: false)]
        case .groupV2Discussion(let structure):
            recipients = structure.group.contactIdentities.map({ $0.toINPerson(withINImage: false) })
                       + [discussionKind.ownedIdentity.toINPerson(withINImage: false)]
        }

        let speakableGroupName = getSpeakableGroupName(discussionKind: discussionKind)
        
        let conversationIdentifier = discussionKind.conversationIdentifier

        // Prepare the intent
        
        let intent = INSendMessageIntent(recipients: recipients,
                                         outgoingMessageType: .outgoingMessageText,
                                         content: nil, // We don't expose the message body to the intent
                                         speakableGroupName: speakableGroupName,
                                         conversationIdentifier: conversationIdentifier,
                                         serviceName: nil,
                                         sender: sender,
                                         attachments: nil)

        // Set group avatar
        
        let groupINImage: INImage? = getGroupINImage(discussionKind: discussionKind)
        
        if let groupINImage, speakableGroupName != nil {
            // Note the previous test: if speakableGroupName is nil, the following line does nothing, even if there is an image.
            intent.setImage(groupINImage, forParameterNamed: \.speakableGroupName)
        }

        // Set message metadata

        let messageOrReaction: MessageOrReactionMetadata = .message(discussionKind: discussionKind, mentions: sentMessage.mentions.map(\.mentionedCryptoId), messageRepliedTo: sentMessage.repliedToMessage)
        intent.donationMetadata = getIntentDonationMetadata(messageOrReaction: messageOrReaction, discussionKind: discussionKind)

        // Return the intent
        
        return intent

    }
    

    // MARK: - Incoming message or reaction
    

    private static func incomingMessageOrReaction(contact: PersistedObvContactIdentityStructure, messageOrReaction: MessageOrReactionMetadata) throws -> INSendMessageIntent {
        
        let sender = contact.toINPerson(withINImage: true)
        let discussionKind = messageOrReaction.discussionKind
        
        let recipients: [INPerson]
        switch discussionKind {
        case .oneToOneDiscussion(let structure):
            guard contact == structure.contactIdentity else { assertionFailure(); throw ObvError.unexpectedError }
            recipients = [contact.ownedIdentity.toINPerson(withINImage: true)]
        case .groupDiscussion(let structure):
            guard structure.contactGroup.contactIdentities.contains(contact) else { assertionFailure(); throw ObvError.unexpectedError }
            recipients = structure.contactGroup.contactIdentities.map({ $0.toINPerson(withINImage: false) }) + [discussionKind.ownedIdentity.toINPerson(withINImage: false)]
        case .groupV2Discussion(let structure):
            guard structure.group.contactIdentities.contains(contact) else { assertionFailure(); throw ObvError.unexpectedError }
            // Include the owned identity so the Intent framework treats this as a group conversation.
            // Omitting it causes a 2-person group to be misclassified as 1:1, losing the group image and title.
            recipients = structure.group.contactIdentities.map({ $0.toINPerson(withINImage: false) }) + [discussionKind.ownedIdentity.toINPerson(withINImage: false)]
        }
        
        let speakableGroupName = getSpeakableGroupName(discussionKind: discussionKind)

        let conversationIdentifier = discussionKind.conversationIdentifier

        // Prepare the intent
        
        let intent = INSendMessageIntent(recipients: recipients,
                                         outgoingMessageType: .outgoingMessageText,
                                         content: nil, // We don't expose the message body to the intent
                                         speakableGroupName: speakableGroupName,
                                         conversationIdentifier: conversationIdentifier,
                                         serviceName: nil,
                                         sender: sender,
                                         attachments: nil)

        // Set group avatar
        
        let groupINImage: INImage? = getGroupINImage(discussionKind: discussionKind)
        
        if let groupINImage, speakableGroupName != nil {
            // Note the previous test: if speakableGroupName is nil, the following line does nothing, even if there is an image. 
            intent.setImage(groupINImage, forParameterNamed: \.speakableGroupName)
        }

        // Set message metadata

        intent.donationMetadata = getIntentDonationMetadata(messageOrReaction: messageOrReaction, discussionKind: discussionKind)
        
        // Return the intent
        
        return intent

    }

}


// MARK: - Helper Functions

extension ObvCommunicationMapper {
    
    
    private static func getIntentDonationMetadata(messageOrReaction: MessageOrReactionMetadata, discussionKind: PersistedDiscussionAbstractStructure.StructureKind) -> INIntentDonationMetadata {
        
        let metadata = INSendMessageIntentDonationMetadata()
        
        switch messageOrReaction {
            
        case .message(discussionKind: let discussionKind, mentions: let mentions, messageRepliedTo: let messageRepliedTo):
            
            switch discussionKind {
            case .oneToOneDiscussion(structure: let structure):
                metadata.mentionsCurrentUser = mentions.contains(structure.contactIdentity.ownedIdentity.cryptoId)
            case .groupDiscussion(structure: let structure):
                metadata.mentionsCurrentUser = mentions.contains(structure.contactGroup.ownedIdentity.cryptoId)
                metadata.recipientCount = structure.contactGroup.contactIdentities.count + 1 // +1 for the owned identity included in recipients
            case .groupV2Discussion(structure: let structure):
                metadata.mentionsCurrentUser = mentions.contains(structure.group.ownedIdentity.cryptoId)
                metadata.recipientCount = structure.group.contactIdentities.count + 1 // +1 for the owned identity included in recipients
            }
            
            metadata.isReplyToCurrentUser = messageRepliedTo?.isPersistedMessageSent ?? false

        case .reaction:
            
            metadata.mentionsCurrentUser = false
            metadata.isReplyToCurrentUser = true
            
        case .vote:
            metadata.mentionsCurrentUser = false
            metadata.isReplyToCurrentUser = true
        }

        return metadata
        
    }
    
    
    private static func getGroupINImage(discussionKind: PersistedDiscussionAbstractStructure.StructureKind) -> INImage? {
        let groupINImage: INImage?
        switch discussionKind {
        case .oneToOneDiscussion:
            groupINImage = nil
        case .groupDiscussion(let structure):
            let groupColor = AppTheme.shared.groupColors(forGroupUid: structure.contactGroup.groupV1Identifier.groupUid)
            let circledSymbol = UIImage.makeCircledSymbol(
                from: SystemIcon.person3Fill.name,
                circleDiameter: ObvINImage.circleDiameter,
                fillColor: groupColor.background,
                symbolColor: groupColor.text)
            groupINImage = ObvINImage.make(photoURL: structure.contactGroup.displayPhotoURL, fallbackImage: circledSymbol)
        case .groupV2Discussion(let structure):
            let groupColor = AppTheme.shared.groupV2Colors(forGroupIdentifier: structure.group.groupIdentifier.appGroupIdentifier)
            let circledSymbol = UIImage.makeCircledSymbol(
                from: SystemIcon.person3Fill.name,
                circleDiameter: ObvINImage.circleDiameter,
                fillColor: groupColor.background,
                symbolColor: groupColor.text)
            groupINImage = ObvINImage.make(photoURL: structure.group.displayPhotoURL, fallbackImage: circledSymbol)
        }
        return groupINImage
    }
    
    
    private static func getSpeakableGroupName(discussionKind: PersistedDiscussionAbstractStructure.StructureKind) -> INSpeakableString? {
        let speakableGroupName: INSpeakableString?
        switch discussionKind {
        case .oneToOneDiscussion:
            speakableGroupName = nil
        case .groupDiscussion(let structure):
            speakableGroupName = INSpeakableString(spokenPhrase: structure.title)
        case .groupV2Discussion(let structure):
            speakableGroupName = INSpeakableString(spokenPhrase: structure.title)
        }
        return speakableGroupName
    }

}


// MARK: - Private types

extension ObvCommunicationMapper {
    
    private enum MessageOrReactionMetadata {
        case message(discussionKind: PersistedDiscussionAbstractStructure.StructureKind, mentions: [ObvCryptoId], messageRepliedTo: RepliedToMessageStructure?)
        case reaction(sentMessageReactedTo: PersistedMessageSentStructure)
        case vote(sentMessageVotedTo: PersistedMessageSentStructure)
        
        var discussionKind: PersistedDiscussionAbstractStructure.StructureKind {
            switch self {
            case .message(discussionKind: let discussionKind, mentions: _, messageRepliedTo: _):
                return discussionKind
            case .reaction(let sentMessageReactedTo):
                return sentMessageReactedTo.discussionKind
            case .vote(let sentMessageVotedTo):
                return sentMessageVotedTo.discussionKind
            }
        }
    }

}


// MARK: - Errors

extension ObvCommunicationMapper {
    
    enum ObvError: Error {
        case unexpectedError
        case couldNotDetermineCallerOfIncomingCall
    }
    
}


// MARK: - Type extensions


extension ObvCryptoId {

    public var toINPersonHandle: INPersonHandle {
        return .init(value: self.description,
                     type: .unknown,
                     label: .init("Olvid"))
    }

}


extension ObvContactIdentifier {

    public var toINPersonHandle: INPersonHandle {
        return .init(value: self.description,
                     type: .unknown,
                     label: .init("Olvid"))
    }

}


extension INPerson {

    /// Canonical Olvid → `INPerson` constructor shared by the main-app donation path
    /// (`ObvCommunicationMapper`) and the SiriKit IntentsExtension. Both paths thunk to this so a
    /// given Olvid identity always materializes into the same `INPerson` shape regardless of which
    /// extension or context built it.
    ///
    /// - Parameters:
    ///   - handle: The `INPersonHandle` (typically `cryptoId.toINPersonHandle` for owned
    ///     identities or `contactIdentifier.toINPersonHandle` for contacts).
    ///   - nameComponents: Full `PersonNameComponents` for the identity. Always attached so Siri
    ///     can apply its own formatting rules.
    ///   - displayName: Pre-resolved display name. Callers decide whether to honor a user-set
    ///     custom name override (e.g. `customOrNormalDisplayName` for contacts).
    ///   - photoURL: Profile photo URL; only consulted when `withImage` is true.
    ///   - cryptoId: Used to derive the fallback circled-character color when `withImage` is true
    ///     and `photoURL` is missing or unreadable.
    ///   - isMe: True iff the identity is an owned identity.
    ///   - withImage: When false the returned `INPerson` carries no image (cheap construction for
    ///     bulk recipient lists). All other fields are always populated.
    public static func olvidPerson(
        handle: INPersonHandle,
        nameComponents: PersonNameComponents,
        displayName: String,
        photoURL: URL?,
        cryptoId: ObvCryptoId,
        isMe: Bool,
        withImage: Bool
    ) -> INPerson {

        let image: INImage?
        if withImage {
            let colors = AppTheme.shared.identityColors(for: cryptoId)
            let circledCharacter = UIImage.makeCircledCharacter(
                fromString: nameComponents.formatted(),
                circleDiameter: ObvINImage.circleDiameter,
                fillColor: colors.background,
                characterColor: colors.text)
            image = ObvINImage.make(
                photoURL: photoURL,
                fallbackImage: circledCharacter)
        } else {
            image = nil
        }

        // suggestionType is deliberately .none: with .socialProfile, iOS's "Siri Found in Apps"
        // feature offers to save our handle (a hex blob containing the contact's *and* the user's
        // own crypto identities, see ObvContactIdentifier.description) into a matched system
        // address book card, leaking Olvid identities to iCloud/Google/Exchange sync and to any
        // app with Contacts access. Siri matching works through customIdentifier regardless.
        return INPerson(personHandle: handle,
                        nameComponents: nameComponents,
                        displayName: displayName,
                        image: image,
                        contactIdentifier: nil,
                        customIdentifier: handle.value,
                        isMe: isMe,
                        suggestionType: .none)

    }

}


extension PersistedObvOwnedIdentityStructure {

    func toINPerson(withINImage: Bool) -> INPerson {
        let nameComponents = self.identityCoreDetails.personNameComponents
        return INPerson.olvidPerson(
            handle: self.cryptoId.toINPersonHandle,
            nameComponents: nameComponents,
            displayName: nameComponents.formatted(.name(style: .short)),
            photoURL: self.photoURL,
            cryptoId: self.cryptoId,
            isMe: true,
            withImage: withINImage)
    }

}


extension PersistedObvContactIdentityStructure {

    func toINPerson(withINImage: Bool) -> INPerson {
        ObvDisplayableLogs.shared.log("[CommunicationInteractor] toINPerson(withINImage: \(withINImage))")
        return INPerson.olvidPerson(
            handle: self.contactIdentifier.toINPersonHandle,
            nameComponents: self.personNameComponents,
            displayName: self.customOrNormalDisplayName,
            photoURL: self.displayPhotoURL,
            cryptoId: self.cryptoId,
            isMe: false,
            withImage: withINImage)
    }

}
