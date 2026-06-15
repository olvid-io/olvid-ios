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
import ObvTypes
import ObvOwnedIdentityChooser
import ObvDesignSystem
import ObvCrypto


extension ObvCryptoId {
    
    @MainActor
    static let sampleDatasForOwnedCryptoId: [Self] = [
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f0000b82ae0c57e570389cb03d5ad93dab4606bda7bbe01c09ce5e423094a8603a61e01693046e10e04606ef4461d31e1aa1819222a0a606a250e91749095a4410778c1")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f000009e171a9c73a0d6e9480b022154c83b13dfa8e4c99496c061c0c35b9b0432b3a014a5393f98a1aead77b813df0afee6b8af7e5f9a5aae6cb55fdb6bc5cc766f8da")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f00002d459c378a0bbc54c8be3e87e82d02347c046c4a50a6db25fe15751d8148671401054f3b14bbd7319a1f6d71746d6345332b92e193a9ea00880dd67b2f10352831")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f000089aebda5ddb3a59942d4fe6e00720b851af1c2d70b6e24e41ac8da94793a6eb70136a23bf11bcd1ccc244ab3477545cc5fee6c60c2b89b8ff2fb339f7ed2ff1f0a")!),
    ]

}


extension ObvAvatarViewModel.CharacterOrIcon {
    
    @MainActor
    static func sampleDataForOwnedCryptoId(_ ownedCryptoId: ObvCryptoId) -> Self {
        switch ownedCryptoId {
        case ObvCryptoId.sampleDatasForOwnedCryptoId[0]:
            return .character("A")
        case ObvCryptoId.sampleDatasForOwnedCryptoId[1]:
            return .character("B")
        case ObvCryptoId.sampleDatasForOwnedCryptoId[2]:
            return .character("C")
        case ObvCryptoId.sampleDatasForOwnedCryptoId[3]:
            return .character("D")
        default:
            return .character("Z")
        }
    }

    
}


extension ObvAvatarViewModel.Colors {
    
    @MainActor
    static func sampleDataForOwnedCryptoId(_ ownedCryptoId: ObvCryptoId) -> Self {
        switch ownedCryptoId {
        case ObvCryptoId.sampleDatasForOwnedCryptoId[0]:
            return .init(foreground: .systemBlue, background: .systemRed)
        case ObvCryptoId.sampleDatasForOwnedCryptoId[1]:
            return .init(foreground: .systemPink, background: .systemBlue)
        case ObvCryptoId.sampleDatasForOwnedCryptoId[2]:
            return .init(foreground: .systemCyan, background: .systemPink)
        case ObvCryptoId.sampleDatasForOwnedCryptoId[3]:
            return .init(foreground: .systemOrange, background: .systemCyan)
        default:
            return .init(foreground: .systemPink, background: .systemCyan)
        }
    }

}


extension URL {
    
    @MainActor static let photoURLs: [URL] = [
        URL(string: "https://dev.olvid.io/avatar00")!,
        URL(string: "https://dev.olvid.io/avatar01")!,
        URL(string: "https://dev.olvid.io/avatar02")!,
        URL(string: "https://dev.olvid.io/avatar03")!,
        URL(string: "https://dev.olvid.io/avatar04")!,
        URL(string: "https://dev.olvid.io/avatar05")!,
        URL(string: "https://dev.olvid.io/avatar06")!,
    ]

    @MainActor
    static func sampleDataForOwnedCryptoId(_ ownedCryptoId: ObvCryptoId) -> Self {
        switch ownedCryptoId {
        case ObvCryptoId.sampleDatasForOwnedCryptoId[0]:
            return Self.photoURLs[0]
        case ObvCryptoId.sampleDatasForOwnedCryptoId[1]:
            return Self.photoURLs[1]
        case ObvCryptoId.sampleDatasForOwnedCryptoId[2]:
            return Self.photoURLs[2]
        case ObvCryptoId.sampleDatasForOwnedCryptoId[3]:
            return Self.photoURLs[3]
        default:
            return Self.photoURLs[4]
        }
    }

}

extension ObvAvatarViewModel {
    
    @MainActor
    static func sampleDatasForOwnedCryptoId(_ ownedCryptoId: ObvCryptoId) -> Self {
        return .init(characterOrIcon: CharacterOrIcon.sampleDataForOwnedCryptoId(ownedCryptoId),
                     colors: Colors.sampleDataForOwnedCryptoId(ownedCryptoId),
                     photoURL: URL.sampleDataForOwnedCryptoId(ownedCryptoId))
    }

}


extension String {
    
    @MainActor
    static func sampleNamesForOwnedCryptoId(_ ownedCryptoId: ObvCryptoId) -> (title: String, subtitle: String) {
        switch ownedCryptoId {
        case ObvCryptoId.sampleDatasForOwnedCryptoId[0]:
            return ("Adam Johnson", "Subtitle")
        case ObvCryptoId.sampleDatasForOwnedCryptoId[1]:
            return ("Diana Torres", "Subtitle")
        case ObvCryptoId.sampleDatasForOwnedCryptoId[2]:
            return ("Jack Richardson", "Subtitle")
        case ObvCryptoId.sampleDatasForOwnedCryptoId[3]:
            return ("Seraphina Alvarez", "Subtitle")
        default:
            return ("Thaddeus Walker", "Subtitle")
        }
    }
    
}


extension OwnedIdentityChooserViewModel.OwnedIdentity {
    
    @MainActor
    static func sampleDataForOwnedCryptoId(_ ownedCryptoId: ObvCryptoId) -> OwnedIdentityChooserViewModel.OwnedIdentity {
        return OwnedIdentityChooserViewModel.OwnedIdentity(
            ownedCryptoId: ownedCryptoId,
            avatarViewModel: ObvAvatarViewModel.sampleDatasForOwnedCryptoId(ownedCryptoId),
            title: String.sampleNamesForOwnedCryptoId(ownedCryptoId).title,
            subtitle: String.sampleNamesForOwnedCryptoId(ownedCryptoId).subtitle,
            totalBadgeCount: Int.random(in: 0..<10),
            showGreenShield: Bool.random(),
            showRedShield: Bool.random(),
            showHiddenProfileIcon: Bool.random())
    }
    
    @MainActor
    static let sampleDatasForOwnedCryptoId: [Self] = [
        Self.sampleDataForOwnedCryptoId(.sampleDatasForOwnedCryptoId[0]),
        Self.sampleDataForOwnedCryptoId(.sampleDatasForOwnedCryptoId[1]),
        Self.sampleDataForOwnedCryptoId(.sampleDatasForOwnedCryptoId[2]),
        Self.sampleDataForOwnedCryptoId(.sampleDatasForOwnedCryptoId[3]),
    ]
    
}


extension UID {
    
    @MainActor
    static var sampleDatas: [UID] = [
        UID(uid: Data(repeating: 0x00, count: 32))!,
        UID(uid: Data(repeating: 0x01, count: 32))!,
    ]

}


extension ObvOwnedDeviceIdentifier {
    
    @MainActor
    static var sampleDatas: [Self] = [
        .init(ownedCryptoId: ObvCryptoId.sampleDatasForOwnedCryptoId[0], deviceUID: UID.sampleDatas[0]),
        .init(ownedCryptoId: ObvCryptoId.sampleDatasForOwnedCryptoId[0], deviceUID: UID.sampleDatas[1]),
    ]
    
}
