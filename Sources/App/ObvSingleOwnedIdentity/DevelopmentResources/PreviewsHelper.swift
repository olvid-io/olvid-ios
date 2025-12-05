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
import ObvDesignSystem
import OlvidUtils


#if DEBUG

extension ObvCryptoId {
    
    @MainActor
    static let sampleOwnedCryptoId: Self = try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f0000b82ae0c57e570389cb03d5ad93dab4606bda7bbe01c09ce5e423094a8603a61e01693046e10e04606ef4461d31e1aa1819222a0a606a250e91749095a4410778c1")!)
    
    @MainActor
    static let sampleContactCryptoId: Self = try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f000009e171a9c73a0d6e9480b022154c83b13dfa8e4c99496c061c0c35b9b0432b3a014a5393f98a1aead77b813df0afee6b8af7e5f9a5aae6cb55fdb6bc5cc766f8da")!)
    
}


extension ObvAvatarViewModel {
    
    static let sampleData: Self = .init(
        characterOrIcon: .character("A"),
        colors: .init(foreground: .blue, background: .red),
        photoURL: nil)
    
}

extension ObvIdentityCoreDetails {
    
    static let sampleData: [Self] = [
        try! .init(firstName: "Barbara",
                   lastName: "Gourde",
                   company: "WorldCompany",
                   position: "CEO",
                   signedUserDetails: nil),
        try! .init(firstName: "Barbaras",
                   lastName: "Gourde",
                   company: "WorldCompany",
                   position: "CEO",
                   signedUserDetails: nil),
    ]
    
}

extension ObvIdentityDetails {
    
    static let sampleData: [Self] = [
        .init(coreDetails: .sampleData[0],
              photoURL: nil),
        .init(coreDetails: .sampleData[1],
              photoURL: nil),
    ]
    
}


extension APIKeyElements {

    static let sampleData: Self = .init(
        status: .valid,
        permissions: [.canCall, .multidevice],
        expirationDate: .now.addingTimeInterval(.init(days: 20)))

}

extension ObvSingleOwnedIdentityView.Model {
    
    @MainActor
    static let sampleData: Self = .init(
        ownedCryptoId: .sampleOwnedCryptoId,
        avatarModel: .sampleData,
        identityDetails: .sampleData[0],
        isActive: true,
        numberOfOwnedDevices: 3,
        apiKeyElements: .sampleData,
        isHidden: false,
        numberOfOtherNonHiddenOwnedIdentities: 1,
        customDisplayName: "Current custom name")
    
}

#endif

