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
import ObvAppTypes
import ObvDesignSystem
import ObvSystemIcon
import ObvTypes
import ObvUICoreData


// Managed-object → Intents conversions. Lives here, alongside the Structure-based conversions in
// `ObvCommunicationMapper`, so both paths share a single home and any divergence is immediately
// visible. `ObvCryptoId.toINPersonHandle` and `ObvContactIdentifier.toINPersonHandle` are defined
// in `ObvCommunicationMapper.swift`.


extension ObvDiscussionIdentifier {

    public var toINPersonHandle: INPersonHandle {
        return .init(value: self.description,
                     type: .unknown)
    }

}


extension PersistedObvContactIdentity {

    /// Resolves this contact into the canonical Olvid `INPerson` (see ``INPerson/olvidPerson(handle:nameComponents:displayName:photoURL:cryptoId:isMe:withImage:)``).
    /// `displayName` honors the user-set custom name override via `customOrNormalDisplayName`.
    /// Pass `withImage: false` for cheap bulk construction (e.g. INMessage recipient lists); all
    /// other fields are always populated so Siri can cross-reference against donations.
    public func toINPerson(withImage: Bool = true) throws -> INPerson {
        let nameComponents = self.personNameComponents ?? PersonNameComponents(givenName: self.customOrFullDisplayName)
        return INPerson.olvidPerson(
            handle: try self.obvContactIdentifier.toINPersonHandle,
            nameComponents: nameComponents,
            displayName: nameComponents.nickname ?? nameComponents.formatted(.name(style: .short)),
            photoURL: self.displayPhotoURL,
            cryptoId: try self.cryptoId,
            isMe: false,
            withImage: withImage)
    }

}


extension PersistedObvOwnedIdentity {

    /// Resolves this owned identity into the canonical Olvid `INPerson` (see ``INPerson/olvidPerson(handle:nameComponents:displayName:photoURL:cryptoId:isMe:withImage:)``).
    /// `displayName` honors the user-set profile alias via `customOrShortDisplayName`.
    public func toINPerson(withImage: Bool = true) throws -> INPerson {
        return INPerson.olvidPerson(
            handle: self.cryptoId.toINPersonHandle,
            nameComponents: self.identityCoreDetails.personNameComponents,
            displayName: self.customOrShortDisplayName,
            photoURL: self.photoURL,
            cryptoId: self.cryptoId,
            isMe: true,
            withImage: withImage)
    }

}


extension PersistedDiscussion {

    public var contactsINPerson: [INPerson]? {
        get throws {
            switch try kind {
            case .oneToOne:
                return nil
            case .groupV1(withContactGroup: let contactGroup):
                return contactGroup?.contactIdentities.compactMap { try? $0.toINPerson(withImage: false) }
            case .groupV2(withGroup: let group):
                return group?.contactsAmongNonPendingOtherMembers.compactMap { try? $0.toINPerson(withImage: false) }
            }
        }
    }

    private var getGroupINImage: INImage? {
        get throws {
            switch try kind {
            case .oneToOne(withContactIdentity: let contactIdentity):
                guard let contactIdentity else { return nil }
                guard let contactCryptoId = try? contactIdentity.cryptoId else { return nil }
                let colors = AppTheme.shared.identityColors(for: contactCryptoId)
                let circledCharacter = UIImage.makeCircledCharacter(
                    fromString: contactIdentity.personNameComponents?.formatted() ?? contactIdentity.customOrFullDisplayName,
                    circleDiameter: ObvINImage.circleDiameter,
                    fillColor: colors.background,
                    characterColor: colors.text)
                return ObvINImage.make(photoURL: contactIdentity.displayPhotoURL, fallbackImage: circledCharacter)
            case .groupV1(withContactGroup: let contactGroup):
                guard let contactGroup else { return nil }
                let groupColor = AppTheme.shared.groupColors(forGroupUid: contactGroup.groupUid)
                let circledSymbol = UIImage.makeCircledSymbol(
                    from: SystemIcon.person3Fill.name,
                    circleDiameter: ObvINImage.circleDiameter,
                    fillColor: groupColor.background,
                    symbolColor: groupColor.text)
                return ObvINImage.make(photoURL: contactGroup.displayPhotoURL, fallbackImage: circledSymbol)
            case .groupV2(withGroup: let group):
                guard let group else { return nil }
                let groupColor = AppTheme.shared.groupV2Colors(forGroupIdentifier: group.groupIdentifier)
                let circledSymbol = UIImage.makeCircledSymbol(
                    from: SystemIcon.person3Fill.name,
                    circleDiameter: ObvINImage.circleDiameter,
                    fillColor: groupColor.background,
                    symbolColor: groupColor.text)
                return ObvINImage.make(photoURL: group.displayPhotoURL, fallbackImage: circledSymbol)
            }
        }
    }

    public func toINPerson(withImage: Bool = true) throws -> INPerson {
        let discussionIdentifier = try self.discussionIdentifier
        return INPerson(personHandle: discussionIdentifier.toINPersonHandle,
                        nameComponents: nil,
                        displayName: self.title,
                        image: withImage ? try? getGroupINImage : nil,
                        contactIdentifier: nil,
                        customIdentifier: discussionIdentifier.description)
    }

}
