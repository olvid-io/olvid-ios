/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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
import ObvCrypto
import ObvDesignSystem
import ObvAppTypes
import ObvSystemIcon
import SwiftUI
import ObvProfilePictureBarButtonItem
import ObvTypes

#if DEBUG

extension ObvCryptoId {
    
    @MainActor
    static let sampleOwnedCryptoId: Self = try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f0000b82ae0c57e570389cb03d5ad93dab4606bda7bbe01c09ce5e423094a8603a61e01693046e10e04606ef4461d31e1aa1819222a0a606a250e91749095a4410778c1")!)
    
    @MainActor
    static let sampleContactCryptoId: Self = try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f000009e171a9c73a0d6e9480b022154c83b13dfa8e4c99496c061c0c35b9b0432b3a014a5393f98a1aead77b813df0afee6b8af7e5f9a5aae6cb55fdb6bc5cc766f8da")!)
    
}


extension ObvAvatarViewModel {
    
    @MainActor
    static let sampleDataForTrustedDetails: Self = .init(
        characterOrIcon: .character("A"),
        colors: .init(foreground: .red, background: .blue),
        photoURL: nil)
    
    @MainActor
    static let sampleDataForPublishedDetails: Self = .init(
        characterOrIcon: .character("A"),
        colors: .init(foreground: .red, background: .blue),
        photoURL: nil)
    
    @MainActor
    static let sampleDataForCustomDetails: Self = .init(
        characterOrIcon: .character("N"),
        colors: .init(foreground: .red, background: .blue),
        photoURL: nil)

}


extension ObvIdentityCoreDetails {
    
    @MainActor
    static let sampleDataForTrustedDetails: Self = try! .init(
        firstName: "Alice",
        lastName: "Wonderland",
        company: "FakeCo",
        position: "CTO",
        signedUserDetails: nil)
    
    @MainActor
    static let sampleDataForPublishedDetails: Self = try! .init(
        firstName: "Alicia",
        lastName: "Wonderland",
        company: "FakeCo",
        position: "CTO",
        signedUserDetails: nil)
    
}


extension ObvIdentityDetails {
    
    @MainActor
    static let sampleDataForTrustedDetails: Self = .init(
        coreDetails: .sampleDataForTrustedDetails,
        photoURL: nil)
    
    @MainActor
    static let sampleDataForPublishedDetails: Self = .init(
        coreDetails: .sampleDataForPublishedDetails,
        photoURL: nil)
    
}


extension ObvContactIdentity {
    
    @MainActor
    static let sampleData: Self = .init(
        contactCryptoId: .sampleContactCryptoId,
        trustedIdentityDetails: .sampleDataForTrustedDetails,
        publishedIdentityDetails: .sampleDataForPublishedDetails,
        ownedCryptoId: .sampleOwnedCryptoId,
        isCertifiedByOwnKeycloak: true,
        isActive: true,
        isRevokedAsCompromised: false,
        isOneToOne: false,
        wasRecentlyOnline: true)

}

extension ObvSingleContactView.Model.CustomDetails {
    
    @MainActor
    static let sampleData: Self = .init(
        nickname: "Nickname",
        avatarModel: .sampleDataForCustomDetails)

}


extension ObvSingleContactView.Model {
  
    @MainActor
    static let sampleData: Self = .init(
        contactIdentifier: ObvContactIdentity.sampleData.contactIdentifier,
        trustedIdentityDetails: ObvContactIdentity.sampleData.trustedIdentityDetails,
        publishedIdentityDetails: ObvContactIdentity.sampleData.publishedIdentityDetails,
        customDetails: CustomDetails.sampleData,
        personalNote: "Some personal note",
        avatarModelFromTrustedDetails: .sampleDataForTrustedDetails,
        avatarModelFromPublishedDetails: .sampleDataForPublishedDetails,
        countOfContactDevices: 2,
        contactDeletionType: .downgradeToNonOneToOne,
        atLeastOneDeviceAllowsThisContactToReceiveMessages: true,
        showReblockView: false,
        oneToOneInvitationSent: false,
        numberOfGroupsInCommon: 2,
        isActive: ObvContactIdentity.sampleData.isActive,
        wasRecentlyOnline: ObvContactIdentity.sampleData.wasRecentlyOnline,
        isOneToOne: ObvContactIdentity.sampleData.isOneToOne)
    
}


extension ObvContactIdentifier {
    
    @MainActor
    static let sampleData: Self = .init(
        contactCryptoId: .sampleContactCryptoId,
        ownedCryptoId: .sampleOwnedCryptoId)

}


extension ContactPublishedDetailsValidationViewModel {
    
    @MainActor
    static let sampleData: Self = .init(
        contactIdentifier: .sampleData,
        trustedDetails: .sampleDataForTrustedDetails,
        publishedDetails: .sampleDataForPublishedDetails,
        avatarModelFromPublishedDetails: .sampleDataForPublishedDetails)

}

#endif
