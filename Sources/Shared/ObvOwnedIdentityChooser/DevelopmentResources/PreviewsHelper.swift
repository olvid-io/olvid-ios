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
import SwiftUI
import ObvTypes
import ObvDesignSystem


extension ObvCryptoId {
    
    @MainActor
    static var sampleDatas: [Self] = [
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f0000b82ae0c57e570389cb03d5ad93dab4606bda7bbe01c09ce5e423094a8603a61e01693046e10e04606ef4461d31e1aa1819222a0a606a250e91749095a4410778c1")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f000009e171a9c73a0d6e9480b022154c83b13dfa8e4c99496c061c0c35b9b0432b3a014a5393f98a1aead77b813df0afee6b8af7e5f9a5aae6cb55fdb6bc5cc766f8da")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f00002d459c378a0bbc54c8be3e87e82d02347c046c4a50a6db25fe15751d8148671401054f3b14bbd7319a1f6d71746d6345332b92e193a9ea00880dd67b2f10352831")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f000089aebda5ddb3a59942d4fe6e00720b851af1c2d70b6e24e41ac8da94793a6eb70136a23bf11bcd1ccc244ab3477545cc5fee6c60c2b89b8ff2fb339f7ed2ff1f0a")!),
    ]
    
}

extension Character {
    
    @MainActor
    static var sampleDatas: [Self] = ["A", "B", "C", "D"]
    
    @MainActor
    static func sampleData(for ownedCryptoId: ObvCryptoId) -> Self {
        let index = ObvCryptoId.sampleDatas.firstIndex(of: ownedCryptoId)!
        return Self.sampleDatas[index]
    }

}

extension Color {
    
    @MainActor
    static var sampleDatas: [Self] = [.red, .cyan, .blue, .green]

    @MainActor
    static func sampleData(for ownedCryptoId: ObvCryptoId) -> Self {
        let index = ObvCryptoId.sampleDatas.firstIndex(of: ownedCryptoId)!
        return Self.sampleDatas[index]
    }

}


extension ObvAvatarViewModel.Colors {
    
    @MainActor
    static var sampleDatas: [Self] = [
        .init(foreground: .red, background: .blue),
        .init(foreground: .cyan, background: .green),
        .init(foreground: .yellow, background: .brown),
        .init(foreground: .orange, background: .magenta),
    ]

    @MainActor
    static func sampleData(for ownedCryptoId: ObvCryptoId) -> Self {
        let index = ObvCryptoId.sampleDatas.firstIndex(of: ownedCryptoId)!
        return Self.sampleDatas[index]
    }
    
}

extension ObvAvatarViewModel {
    
    @MainActor
    static func sampleData(for ownedCryptoId: ObvCryptoId) -> Self {
        return .init(characterOrIcon: .character(Character.sampleData(for: ownedCryptoId)),
                     colors: ObvAvatarViewModel.Colors.sampleData(for: ownedCryptoId),
                     photoURL: nil)
    }
    
}

extension String {
    
    @MainActor
    static var sampleTitles: [Self] = ["Alice", "Bob", "Charlie", "Davina"]

    @MainActor
    static func sampleTitles(for ownedCryptoId: ObvCryptoId) -> Self {
        let index = ObvCryptoId.sampleDatas.firstIndex(of: ownedCryptoId)!
        return Self.sampleTitles[index]
    }

    @MainActor
    static var sampleSubtitles: [Self] = ["Subtitle 1", "Subtitle 2", "Subtitle 3", "Subtitle 4"]

    @MainActor
    static func sampleSubtitles(for ownedCryptoId: ObvCryptoId) -> Self {
        let index = ObvCryptoId.sampleDatas.firstIndex(of: ownedCryptoId)!
        return Self.sampleSubtitles[index]
    }

}

extension OwnedIdentityChooserViewModel.OwnedIdentity {
    
    @MainActor
    static func sampleData(for ownedCryptoId: ObvCryptoId) -> Self {
        .init(ownedCryptoId: ownedCryptoId,
              avatarViewModel: ObvAvatarViewModel.sampleData(for: ownedCryptoId),
              title: String.sampleTitles(for: ownedCryptoId),
              subtitle: String.sampleSubtitles(for: ownedCryptoId),
              totalBadgeCount: Int.random(in: 0..<10),
              showGreenShield: Bool.random(),
              showRedShield: Bool.random(),
              showHiddenProfileIcon: Bool.random())
    }
    
}


extension [OwnedIdentityChooserViewModel.OwnedIdentity] {
    
    @MainActor
    static var sampleData: Self {
        var array = [OwnedIdentityChooserViewModel.OwnedIdentity]()
        for ownedCryptoId in ObvCryptoId.sampleDatas {
            array.append(.sampleData(for: ownedCryptoId))
        }
        return array
    }
    
}


extension OwnedIdentityChooserViewModel {
    
    @MainActor
    static var sampleData: Self {
        .init(ownedIdentities: [OwnedIdentity].sampleData)
    }
    
}
