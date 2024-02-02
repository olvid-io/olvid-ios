/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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
@available(iOS 14.0, *)
final class IntentManagerUtils {

    fileprivate static let log = OSLog(subsystem: ObvMessengerConstants.logSubsystem, category: String(describing: IntentManagerUtils.self))

    static let thumbnailPhotoSide = CGFloat(300)

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

@available(iOS 14.0, *)
extension IntentManagerUtils {

    fileprivate static func createINImage(photoURL: URL?, fallbackImage: UIImage?, storingPNGPhotoThumbnailAtURL thumbnailURL: URL?, thumbnailSide: CGFloat) -> INImage? {

        let pngData: Data?
        if let url = photoURL,
           let cgImage = UIImage(contentsOfFile: url.path)?.cgImage?.downsizeToSize(CGSize(width: thumbnailSide, height: thumbnailSide)),
           let _pngData = UIImage(cgImage: cgImage).pngData() {
            pngData = _pngData
        } else {
            pngData = fallbackImage?.pngData()
        }

        let image: INImage?
        if let pngData = pngData {
            if let thumbnailURL = thumbnailURL {
                do {
                    try pngData.write(to: thumbnailURL)
                    image = INImage(url: thumbnailURL)
                } catch {
                    os_log("Could not create PNG thumbnail file for contact", log: Self.log, type: .fault)
                    image = INImage(imageData: pngData)
                }
            } else {
                image = INImage(imageData: pngData)
            }
        } else {
            image = nil
        }
        return image
    }

}

// MARK: INSendMessageIntent creation

@available(iOS 14.0, *)
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
        if let groupINImage {
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

    @available(iOS 14.0, *)
    init(groupDiscussion: PersistedGroupDiscussion.Structure, urlForStoringPNGThumbnail: URL?, thumbnailPhotoSide: CGFloat) {
        let contactGroup = groupDiscussion.contactGroup
        let contactIdentities = contactGroup.contactIdentities
        var groupRecipients = [INPerson]()
        for contactIdentity in contactIdentities {
            let inPerson = contactIdentity.createINPerson(storingPNGPhotoThumbnailAtURL: urlForStoringPNGThumbnail, thumbnailSide: thumbnailPhotoSide)
            groupRecipients.append(inPerson)
        }
        self.groupRecipients = groupRecipients
        self.speakableGroupName = INSpeakableString(spokenPhrase: groupDiscussion.title)
        self.groupINImage = contactGroup.createINImage(storingPNGPhotoThumbnailAtURL: urlForStoringPNGThumbnail,
                                                       thumbnailSide: thumbnailPhotoSide)
    }

    @available(iOS 14.0, *)
    init(groupDiscussion: PersistedGroupV2Discussion.Structure, urlForStoringPNGThumbnail: URL?, thumbnailPhotoSide: CGFloat) {
        let group = groupDiscussion.group
        let contactIdentities = group.contactIdentities
        var groupRecipients = [INPerson]()
        for contactIdentity in contactIdentities {
            let inPerson = contactIdentity.createINPerson(storingPNGPhotoThumbnailAtURL: urlForStoringPNGThumbnail, thumbnailSide: thumbnailPhotoSide)
            groupRecipients.append(inPerson)
        }
        self.groupRecipients = groupRecipients
        self.speakableGroupName = INSpeakableString(spokenPhrase: groupDiscussion.title)
        self.groupINImage = group.createINImage(storingPNGPhotoThumbnailAtURL: urlForStoringPNGThumbnail,
                                                thumbnailSide: thumbnailPhotoSide)
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

    @available(iOS 14.0, *)
    init(messageSent: PersistedMessageSent.Structure, urlForStoringPNGThumbnail: URL?, thumbnailPhotoSide: CGFloat) {
        self.discussionPermanentID = messageSent.discussionPermanentID
        let discussionKind = messageSent.discussionKind
        self.ownedINPerson = discussionKind.ownedIdentity.createINPerson(storingPNGPhotoThumbnailAtURL: urlForStoringPNGThumbnail, thumbnailSide: thumbnailPhotoSide)

        switch discussionKind {
        case .oneToOneDiscussion(let structure):
            let contactINPerson = structure.contactIdentity.createINPerson(storingPNGPhotoThumbnailAtURL: urlForStoringPNGThumbnail, thumbnailSide: thumbnailPhotoSide)
            self.recipients = .oneToOne(contactINPerson)
        case .groupDiscussion(let structure):
            let groupInfos = GroupInfos(groupDiscussion: structure,
                                        urlForStoringPNGThumbnail: urlForStoringPNGThumbnail,
                                        thumbnailPhotoSide: thumbnailPhotoSide)
            self.recipients = .group(groupInfos)
        case .groupV2Discussion(let structure):
            let groupInfos = GroupInfos(groupDiscussion: structure,
                                        urlForStoringPNGThumbnail: urlForStoringPNGThumbnail,
                                        thumbnailPhotoSide: thumbnailPhotoSide)
            self.recipients = .group(groupInfos)
        }
    }
}


@available(iOS 14.0, *)
extension PersistedObvContactIdentity.Structure {

    var personHandle: INPersonHandle {
        INPersonHandle(value: self.objectPermanentID.description, type: .unknown, label: .other)
    }

    func createINPerson(storingPNGPhotoThumbnailAtURL thumbnailURL: URL?, thumbnailSide: CGFloat) -> INPerson {

        let fillColor = cryptoId.colors.background
        let characterColor = cryptoId.colors.text
        let circledCharacter = UIImage.makeCircledCharacter(fromString: fullDisplayName,
                                                            circleDiameter: thumbnailSide,
                                                            fillColor: fillColor,
                                                            characterColor: characterColor)
        let image = IntentManagerUtils.createINImage(photoURL: displayPhotoURL,
                                                     fallbackImage: circledCharacter,
                                                     storingPNGPhotoThumbnailAtURL: thumbnailURL,
                                                     thumbnailSide: thumbnailSide)

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

@available(iOS 14.0, *)
extension PersistedObvOwnedIdentity.Structure {

    var personHandle: INPersonHandle {
        INPersonHandle(value: self.objectPermanentID.description, type: .unknown, label: .other)
    }

    func createINPerson(storingPNGPhotoThumbnailAtURL thumbnailURL: URL?, thumbnailSide: CGFloat) -> INPerson {

        let fillColor = cryptoId.colors.background
        let characterColor = cryptoId.colors.text
        let circledCharacter = UIImage.makeCircledCharacter(fromString: fullDisplayName,
                                                            circleDiameter: thumbnailSide,
                                                            fillColor: fillColor,
                                                            characterColor: characterColor)
        let image = IntentManagerUtils.createINImage(photoURL: photoURL,
                                                     fallbackImage: circledCharacter,
                                                     storingPNGPhotoThumbnailAtURL: thumbnailURL,
                                                     thumbnailSide: thumbnailSide)

        return INPerson(personHandle: personHandle,
                        nameComponents: identityCoreDetails.personNameComponents,
                        displayName: fullDisplayName,
                        image: image,
                        contactIdentifier: nil,
                        customIdentifier: nil,
                        isMe: true)
    }
}

@available(iOS 14.0, *)
fileprivate extension PersistedContactGroup.Structure {

    func createINImage(storingPNGPhotoThumbnailAtURL thumbnailURL: URL?, thumbnailSide: CGFloat) -> INImage? {
        let groupColor = AppTheme.shared.groupColors(forGroupUid: groupUid, using: ObvMessengerSettings.Interface.identityColorStyle)
        let circledSymbol = UIImage.makeCircledSymbol(from: SystemIcon.person3Fill.systemName,
                                                      circleDiameter: thumbnailSide,
                                                      fillColor: groupColor.background,
                                                      symbolColor: groupColor.text)
        return IntentManagerUtils.createINImage(photoURL: displayPhotoURL,
                                                fallbackImage: circledSymbol,
                                                storingPNGPhotoThumbnailAtURL: thumbnailURL,
                                                thumbnailSide: thumbnailSide)
    }
}

@available(iOS 14.0, *)
fileprivate extension PersistedGroupV2.Structure {

    func createINImage(storingPNGPhotoThumbnailAtURL thumbnailURL: URL?, thumbnailSide: CGFloat) -> INImage? {
        let groupColor = AppTheme.shared.groupV2Colors(forGroupIdentifier: groupIdentifier)
        let circledSymbol = UIImage.makeCircledSymbol(from: SystemIcon.person3Fill.systemName,
                                                      circleDiameter: thumbnailSide,
                                                      fillColor: groupColor.background,
                                                      symbolColor: groupColor.text)
        return IntentManagerUtils.createINImage(photoURL: displayPhotoURL,
                                                fallbackImage: circledSymbol,
                                                storingPNGPhotoThumbnailAtURL: thumbnailURL,
                                                thumbnailSide: thumbnailSide)
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
