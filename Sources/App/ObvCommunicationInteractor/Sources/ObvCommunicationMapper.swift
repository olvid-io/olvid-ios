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
import Intents
import ObvTypes
import ObvDesignSystem
import ObvSettings
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
            recipients = structure.contactGroup.contactIdentities.map({ $0.toINPerson(withINImage: false) })
        case .groupV2Discussion(let structure):
            recipients = structure.group.contactIdentities.map({ $0.toINPerson(withINImage: false) })
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
            // Although it would make more sense, we don't filter out the sender. In case the group only contains two participants (including us), the Intent frameworks would consider it's a one2one message
            // and wouldn't display the expected group image, title, etc.
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
                metadata.recipientCount = structure.contactGroup.contactIdentities.count
            case .groupV2Discussion(structure: let structure):
                metadata.mentionsCurrentUser = mentions.contains(structure.group.ownedIdentity.cryptoId)
                metadata.recipientCount = structure.group.contactIdentities.count
            }
            
            metadata.isReplyToCurrentUser = messageRepliedTo?.isPersistedMessageSent ?? false

        case .reaction:
            
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
            let groupColor = AppTheme.shared.groupColors(forGroupUid: structure.contactGroup.groupV1Identifier.groupUid, using: ObvMessengerSettings.Interface.identityColorStyle)
            let circledSymbol = UIImage.makeCircledSymbol(
                from: SystemIcon.person3Fill.name,
                circleDiameter: Self.circleDiameter,
                fillColor: groupColor.background,
                symbolColor: groupColor.text)
            groupINImage = Self.createINImage(photoURL: structure.contactGroup.displayPhotoURL, fallbackImage: circledSymbol)
        case .groupV2Discussion(let structure):
            let groupColor = AppTheme.shared.groupV2Colors(forGroupIdentifier: structure.group.groupIdentifier.appGroupIdentifier, using: ObvMessengerSettings.Interface.identityColorStyle)
            let circledSymbol = UIImage.makeCircledSymbol(
                from: SystemIcon.person3Fill.name,
                circleDiameter: Self.circleDiameter,
                fillColor: groupColor.background,
                symbolColor: groupColor.text)
            groupINImage = Self.createINImage(photoURL: structure.group.displayPhotoURL, fallbackImage: circledSymbol)
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
        
    
    private static let circleDiameter = CGFloat(192)

    
    fileprivate static func createINImage(photoURL: URL?, fallbackImage: UIImage?) -> INImage? {
        
        guard photoURL != nil || fallbackImage != nil else { return nil }
        
        let imageSideSize = CGFloat(300)
        
        // We do not use the INImage.init(url:) intializer. We experienced issues with this API (in particular, images would
        // not always show in the standard share sheet API). Instead, we always use the INImage.init(imageData:) API
        // using a downsized image. Note that this downsizing is "dangerous" as this method is also used in the notification
        // extension, which must have a limited memory footprint. For this reason, we make sure that we only create one
        // INImage for each notification.
        
        if let photoURL,
           FileManager.default.fileExists(atPath: photoURL.path),
           let image = UIImage(contentsOfFile: photoURL.path),
           let downSizedImage = image.downsizeIfRequired(maxWidth: imageSideSize, maxHeight: imageSideSize),
           let imageData = downSizedImage.pngData() {
            return INImage(imageData: imageData)
        }
        
        if let fallbackImage,
           let downSizedImage = fallbackImage.downsizeIfRequired(maxWidth: imageSideSize, maxHeight: imageSideSize),
           let imageData = downSizedImage.pngData() {
            return INImage(imageData: imageData)
        }
        
        assertionFailure("Since at least one image source was provided, we expect to be able to return an INImage")
        
        return nil
        
    }

}


// MARK: - Private types

extension ObvCommunicationMapper {
    
    private enum MessageOrReactionMetadata {
        case message(discussionKind: PersistedDiscussionAbstractStructure.StructureKind, mentions: [ObvCryptoId], messageRepliedTo: RepliedToMessageStructure?)
        case reaction(sentMessageReactedTo: PersistedMessageSentStructure)
        var discussionKind: PersistedDiscussionAbstractStructure.StructureKind {
            switch self {
            case .message(discussionKind: let discussionKind, mentions: _, messageRepliedTo: _):
                return discussionKind
            case .reaction(let sentMessageReactedTo):
                return sentMessageReactedTo.discussionKind
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
    
    var toINPersonHandle: INPersonHandle {
        return .init(value: self.description,
                     type: .unknown,
                     label: .init("Olvid ID"))
    }
    
}


extension ObvContactIdentifier {
    
    var toINPersonHandle: INPersonHandle {
        return .init(value: self.description,
                     type: .unknown,
                     label: .init("Olvid ID"))
    }

}


extension PersistedObvOwnedIdentityStructure {
    
    func toINPerson(withINImage: Bool) -> INPerson {
        
        let nameComponents = self.identityCoreDetails.personNameComponents
        let personHandle = self.cryptoId.toINPersonHandle
        
        let image: INImage?
        if withINImage {
            let colors = AppTheme.shared.identityColors(for: self.cryptoId, using: ObvMessengerSettings.Interface.identityColorStyle)
            let circledCharacter = UIImage.makeCircledCharacter(
                fromString: nameComponents.formatted(),
                circleDiameter: Helpers.circleDiameter,
                fillColor: colors.background,
                characterColor: colors.text)
            image = Helpers.createINImage(
                photoURL: self.photoURL,
                fallbackImage: circledCharacter)
        } else {
            image = nil
        }
        
        let person = INPerson(personHandle: personHandle,
                              nameComponents: nameComponents,
                              displayName: nameComponents.formatted(.name(style: .short)),
                              image: image,
                              contactIdentifier: nil,
                              customIdentifier: personHandle.value,
                              isMe: true,
                              suggestionType: .socialProfile)
        
        return person
        
    }
    
}


extension PersistedObvContactIdentityStructure {
    
    func toINPerson(withINImage: Bool) -> INPerson {
        
        ObvDisplayableLogs.shared.log("[CommunicationInteractor] toINPerson(withINImage: \(withINImage))")

        let nameComponents = self.personNameComponents
        let personHandle = self.contactIdentifier.toINPersonHandle
        
        let image: INImage?
        if withINImage {
            let colors = AppTheme.shared.identityColors(for: self.cryptoId, using: ObvMessengerSettings.Interface.identityColorStyle)
            let circledCharacter = UIImage.makeCircledCharacter(
                fromString: nameComponents.formatted(),
                circleDiameter: Helpers.circleDiameter,
                fillColor: colors.background,
                characterColor: colors.text)
            image = Helpers.createINImage(
                photoURL: self.displayPhotoURL,
                fallbackImage: circledCharacter)
        } else {
            image = nil
        }
        
        ObvDisplayableLogs.shared.log("[CommunicationInteractor] Will create INPerson (image is set: \(image != nil))")

        let person = INPerson(personHandle: personHandle,
                              nameComponents: nameComponents,
                              displayName: nameComponents.formatted(.name(style: .short)),
                              image: image,
                              contactIdentifier: nil,
                              customIdentifier: personHandle.value,
                              isMe: false,
                              suggestionType: .socialProfile)
        
        return person

    }
    
}



// MARK: - Private helpers

fileprivate struct Helpers {
    
    static let circleDiameter = CGFloat(192)
    
    static func createINImage(photoURL: URL?, fallbackImage: UIImage?) -> INImage? {
        
        guard photoURL != nil || fallbackImage != nil else { return nil }
        
        let imageSideSize = CGFloat(300)
        
        // We do not use the INImage.init(url:) intializer. We experienced issues with this API (in particular, images would
        // not always show in the standard share sheet API). Instead, we always use the INImage.init(imageData:) API
        // using a downsized image. Note that this downsizing is "dangerous" as this method is also used in the notification
        // extension, which must have a limited memory footprint. For this reason, we make sure that we only create one
        // INImage for each notification.
        
        if let photoURL,
           FileManager.default.fileExists(atPath: photoURL.path),
           let image = UIImage(contentsOfFile: photoURL.path),
           let downSizedImage = image.downsizeIfRequired(maxWidth: imageSideSize, maxHeight: imageSideSize),
           let imageData = downSizedImage.pngData() {
            return INImage(imageData: imageData)
        }
        
        if let fallbackImage,
           let downSizedImage = fallbackImage.downsizeIfRequired(maxWidth: imageSideSize, maxHeight: imageSideSize),
           let imageData = downSizedImage.pngData() {
            return INImage(imageData: imageData)
        }
        
        assertionFailure("Since at least one image source was provided, we expect to be able to return an INImage")
        
        return nil
        
    }

}
