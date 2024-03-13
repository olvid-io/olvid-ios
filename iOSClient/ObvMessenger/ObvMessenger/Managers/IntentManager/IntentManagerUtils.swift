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
import UIKit
import os.log
import ObvUI
import ObvUICoreData
import UI_SystemIcon
import ObvSettings
import ObvDesignSystem


/// IntentManager utilities that can be used by all extentions.
final class IntentManagerUtils {

    fileprivate static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: IntentManagerUtils.self))

    /// One-stop method called when this manager needs to donate an `INSendMessageIntent` object to the system.
    ///
    /// Systematically using this method allows to make sure that users preferences are always taken into account, i.e., that we only perform donations if the global or discussion local configuration lets us do so.
    /// Moreover, we can make sure we *never* perform a donation concerning a hidden profile.
    static func makeDonation(discussionKind: PersistedDiscussion.StructureKind,
                             intent: INSendMessageIntent,
                             direction: INInteractionDirection) async {

        guard discussionKind.localConfiguration.performInteractionDonation ?? ObvMessengerSettings.Discussions.performInteractionDonation else { return }
        guard !discussionKind.ownedIdentity.isHidden else { return }

        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = direction
        interaction.groupIdentifier = discussionKind.interactionGroupIdentifier
        do {
            try await interaction.donate()
            os_log("🎁 Successfully donated interaction", log: Self.log, type: .info)
        } catch {
            assertionFailure()
            os_log("🎁 Interaction donation failed: %{public}@", log: Self.log, type: .fault, error.localizedDescription)
        }
    }
    
}

// MARK: INImage Utils

extension IntentManagerUtils {

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

// MARK: INSendMessageIntent creation

extension IntentManagerUtils {

    static func getSendMessageIntentForMessageSent(infos: SentMessageIntentInfos) -> INSendMessageIntent {
        let recipients = infos.recipients.persons
        var speakableGroupName: INSpeakableString?
        if let groupInfos = infos.recipients.groupInfos {
            speakableGroupName = groupInfos.speakableGroupName
        }
        let sender = infos.ownedINPerson

        return getSendMessageIntent(recipients: recipients,
                                    sender: sender,
                                    speakableGroupName: speakableGroupName,
                                    groupINImage: infos.recipients.groupInfos?.groupINImage,
                                    conversationIdentifier: infos.conversationIdentifier)
    }

    static func getSendMessageIntent(recipients: [INPerson],
                                     sender: INPerson,
                                     speakableGroupName: INSpeakableString?,
                                     groupINImage: INImage?,
                                     conversationIdentifier: String) -> INSendMessageIntent {
        let intent = INSendMessageIntent(
            recipients: recipients,
            outgoingMessageType: .outgoingMessageText,
            content: nil, // Do not expose message body to intent
            speakableGroupName: speakableGroupName,
            conversationIdentifier: conversationIdentifier,
            serviceName: nil,
            sender: sender,
            attachments: nil)
        if let groupINImage, speakableGroupName != nil {
            // Note the previous test: if speakableGroupName is nil, the following line does nothing, even if there is an image.
            intent.setImage(groupINImage, forParameterNamed: \.speakableGroupName)
        }
        return intent
    }

}


// MARK: - GroupInfos

struct GroupInfos {

    let groupRecipients: [INPerson]
    let speakableGroupName: INSpeakableString
    let groupINImage: INImage?

    init(groupDiscussion: PersistedGroupDiscussion.Structure, withINImage: Bool) {
        let contactGroup = groupDiscussion.contactGroup
        let contactIdentities = contactGroup.contactIdentities
        var groupRecipients = [INPerson]()
        for contactIdentity in contactIdentities {
            let inPerson = contactIdentity.createINPerson(withINImage: false) // The only INImage we need is the one of the group
            groupRecipients.append(inPerson)
        }
        self.groupRecipients = groupRecipients
        self.speakableGroupName = INSpeakableString(spokenPhrase: groupDiscussion.title)
        self.groupINImage = withINImage ? contactGroup.createINImage() : nil
    }

    init(groupDiscussion: PersistedGroupV2Discussion.Structure, withINImage: Bool) {
        let group = groupDiscussion.group
        let contactIdentities = group.contactIdentities
        var groupRecipients = [INPerson]()
        for contactIdentity in contactIdentities {
            let inPerson = contactIdentity.createINPerson(withINImage: false) // The only INImage we need is the one of the group
            groupRecipients.append(inPerson)
        }
        self.groupRecipients = groupRecipients
        self.speakableGroupName = INSpeakableString(spokenPhrase: groupDiscussion.title)
        self.groupINImage = withINImage ? group.createINImage() : nil
    }

}

// MARK: - Intents informations

enum SentMessageIntentInfosRecipients {
    case oneToOne(_: INPerson)
    case group(_: GroupInfos)

    var persons: [INPerson] {
        switch self {
        case .oneToOne(let contact):
            return [contact]
        case .group(let groupInfos):
            return groupInfos.groupRecipients
        }
    }

    var groupInfos: GroupInfos? {
        switch self {
        case .oneToOne: return nil
        case .group(let groupInfos): return groupInfos
        }
    }
}

// MARK: - SentMessageIntentInfos

struct SentMessageIntentInfos {

    let discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>
    let ownedINPerson: INPerson
    let recipients: SentMessageIntentInfosRecipients

    var conversationIdentifier: String { discussionPermanentID.description }

    init(messageSent: PersistedMessageSent.Structure) {
        self.discussionPermanentID = messageSent.discussionPermanentID
        let discussionKind = messageSent.discussionKind
        self.ownedINPerson = discussionKind.ownedIdentity.createINPerson(withINImage: false)

        switch discussionKind {
        case .oneToOneDiscussion(let structure):
            let contactINPerson = structure.contactIdentity.createINPerson(withINImage: true)
            self.recipients = .oneToOne(contactINPerson)
        case .groupDiscussion(let structure):
            let groupInfos = GroupInfos(groupDiscussion: structure, withINImage: true)
            self.recipients = .group(groupInfos)
        case .groupV2Discussion(let structure):
            let groupInfos = GroupInfos(
                groupDiscussion: structure, withINImage: true)
            self.recipients = .group(groupInfos)
        }
    }
}


extension PersistedObvContactIdentity.Structure {

    static let circleDiameter = CGFloat(192)
    
    var personHandle: INPersonHandle {
        INPersonHandle(value: self.objectPermanentID.description, type: .unknown, label: .other)
    }

    func createINPerson(withINImage: Bool) -> INPerson {

        let fillColor = cryptoId.colors.background
        let characterColor = cryptoId.colors.text
        let image: INImage?
        if withINImage {
            let circledCharacter = UIImage.makeCircledCharacter(
                fromString: fullDisplayName,
                circleDiameter: Self.circleDiameter,
                fillColor: fillColor,
                characterColor: characterColor)
            image = IntentManagerUtils.createINImage(
                photoURL: displayPhotoURL,
                fallbackImage: circledCharacter)
        } else {
            image = nil
        }

        return INPerson(personHandle: personHandle,
                        nameComponents: personNameComponents,
                        displayName: customOrFullDisplayName,
                        image: image,
                        contactIdentifier: nil,
                        customIdentifier: nil,
                        isMe: false)
    }
}

// MARK: - Structures to INPerson helper

extension PersistedObvOwnedIdentity.Structure {

    static let circleDiameter = PersistedObvContactIdentity.Structure.circleDiameter

    var personHandle: INPersonHandle {
        INPersonHandle(value: self.objectPermanentID.description, type: .unknown, label: .other)
    }

    func createINPerson(withINImage: Bool) -> INPerson {

        let fillColor = cryptoId.colors.background
        let characterColor = cryptoId.colors.text
        let image: INImage?
        if withINImage {
            let circledCharacter = UIImage.makeCircledCharacter(
                fromString: fullDisplayName,
                circleDiameter: Self.circleDiameter,
                fillColor: fillColor,
                characterColor: characterColor)
            image = IntentManagerUtils.createINImage(
                photoURL: photoURL,
                fallbackImage: circledCharacter)
        } else {
            image = nil
        }

        return INPerson(personHandle: personHandle,
                        nameComponents: identityCoreDetails.personNameComponents,
                        displayName: fullDisplayName,
                        image: image,
                        contactIdentifier: nil,
                        customIdentifier: nil,
                        isMe: true)
    }
}

fileprivate extension PersistedContactGroup.Structure {

    static let circleDiameter = PersistedObvContactIdentity.Structure.circleDiameter

    func createINImage() -> INImage? {
        let groupColor = AppTheme.shared.groupColors(forGroupUid: groupUid, using: ObvMessengerSettings.Interface.identityColorStyle)
        let circledSymbol = UIImage.makeCircledSymbol(
            from: SystemIcon.person3Fill.systemName,
            circleDiameter: Self.circleDiameter,
            fillColor: groupColor.background,
            symbolColor: groupColor.text)
        return IntentManagerUtils.createINImage(
            photoURL: displayPhotoURL,
            fallbackImage: circledSymbol)
    }
}

fileprivate extension PersistedGroupV2.Structure {

    static let circleDiameter = PersistedObvContactIdentity.Structure.circleDiameter

    func createINImage() -> INImage? {
        let groupColor = AppTheme.shared.groupV2Colors(forGroupIdentifier: groupIdentifier)
        let circledSymbol = UIImage.makeCircledSymbol(
            from: SystemIcon.person3Fill.systemName,
            circleDiameter: Self.circleDiameter,
            fillColor: groupColor.background,
            symbolColor: groupColor.text)
        return IntentManagerUtils.createINImage(
            photoURL: displayPhotoURL,
            fallbackImage: circledSymbol)
    }
}

extension ObvManagedObjectPermanentID<PersistedDiscussion> {

    var interactionGroupIdentifier: String {
        self.description
    }

}

fileprivate extension PersistedDiscussion.StructureKind {

    var interactionGroupIdentifier: String {
        self.discussionPermanentID.interactionGroupIdentifier
    }

}
