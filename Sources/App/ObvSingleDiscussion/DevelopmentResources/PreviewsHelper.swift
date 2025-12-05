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

import SwiftUI
import ObvTypes
import ObvDesignSystem


#if DEBUG

extension ObvCryptoId {
    
    @MainActor
    static let sampleDatasForOwnedCryptoId: Self = try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f0000b82ae0c57e570389cb03d5ad93dab4606bda7bbe01c09ce5e423094a8603a61e01693046e10e04606ef4461d31e1aa1819222a0a606a250e91749095a4410778c1")!)
    
    @MainActor
    static let sampleDatasForContactCryptoId: [Self] = [
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000153c2183e6feef914ef20ae0f2ce4dd025022221b0bfdf22fb16859feac477fa0023713e65219d2c01f6feb26f9d2a390fd9afce7389f7ae22884f0efccad74c83")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000a7cc11bc3d5b0aaff7689da45478d11e3ac216a84fda1eee483e69d5f38239ca0087679c83bab21cd7ac8ffa73f1494b574364a8e51a99c040f7900b71d3878ac6")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f00001c94bfc08515742d03156b104173bb911e761fa388ed008773e3854f1bf3bb31003f0b55bc89f59d3c9e7eb2a74437a0fe90696318888676869fda77ed0dcdcc55")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000aeaf4fb1ed5cdbdb4ed6c8614fc4706dee09e68425d0086ce4b4ce47d8f4b9f70013013f1ea4b9ce185a35d2d6951299eba3a3a3a8a830f4c2635c74fcec04ac14")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000b9d6817d5e4461249b5901c8fbb85d0dd68c0ff42b03920ff04ff8f00eb8f6f4000cf3ca06cc84cc1759a9d116b89beba5899fc338a29ecff0dd0bb09afe575a7b")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000bed9ed0323efe2d2b3bfa4f1f74a3e5cacd65e0dc30190e241076f247059282a00a36cc9ae36bb78bef9543169e174cf4bca438ad62866aaaf61554882348afc5f")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f00004356b99304f36dc3357c3b22f0a8396142e89037dd8b8eb2a94211f33a8b3c3a00add92b3a7a09e2850d5b06d0658a62ce41e47b032aa6ad24c7ce127676d8c892")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000dea417bbd7de15fbb5f2bc00618bb248f83304c70e50034ae43483f25804b099003a8979bf0995d97fe01bf095c5776a6da0bf3adc02f47b80e8f7aa9b663b5632")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000cc46182a887b2de7270ee55e7dd363b2f3e56c9384d2107e3528ba026e79af9d00646dc7ed94957c1466e792f118ddcfce6c6b1e560821cb91929192a80e2f83bc")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000c3ce6859a5812f36b84212e1970bf30b9f2281a6d13be56ba47381e7d9deae39005cacf6473c4cd8cfeb295e86527f9202ddfde8d310d0fe16c199380d479fc703")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f000034da1b3b1be617df647d4a7c1e5ffb47326e7f0a3c5f8a0031134eb33333ab7b006015bd86d4e90bcb6e4964020baafd7b967c0211d285a4aa2e78b0120efa8320")!),
    ]

    
}

extension ObvReactionsCountViewModel.ReactionAndCount {
    
    @MainActor
    static var sampleData: [Self] = [
        .init(emoji: "😅", count: Int.random(in: 1...20)),
        .init(emoji: "😇", count: Int.random(in: 1...20)),
        .init(emoji: "🫡", count: Int.random(in: 1...20)),
        .init(emoji: "🥳", count: Int.random(in: 1...20)),
        .init(emoji: "🍾", count: Int.random(in: 1...20)),
        .init(emoji: "🎉", count: Int.random(in: 1...20)),
        .init(emoji: "❤️", count: Int.random(in: 1...20)),
        .init(emoji: "😈", count: Int.random(in: 1...20)),
        .init(emoji: "😍", count: Int.random(in: 1...20)),
        .init(emoji: "🕊️", count: Int.random(in: 1...20)),
        .init(emoji: "🙌", count: Int.random(in: 1...20)),
        .init(emoji: "☝️", count: Int.random(in: 1...20)),
        .init(emoji: "🥸", count: Int.random(in: 1...20)),
        .init(emoji: "😉", count: Int.random(in: 1...20)),
    ]
    
}


extension ObvReactionsCountViewModel {
    
    @MainActor
    static var sampleData: Self {
        .init(reactionsAndCount: ReactionAndCount.sampleData)
    }
    
}


extension ObvAvatarViewModel.Colors {
    
    @MainActor
    static func sampleDataForOwnedCryptoId(_ ownedCryptoId: ObvCryptoId) -> Self {
        switch ownedCryptoId {
        case ObvCryptoId.sampleDatasForOwnedCryptoId:
            return .init(foreground: .red, background: .gray)
        default:
            assertionFailure()
            return .init(foreground: .systemPink, background: .systemCyan)
        }
    }

    @MainActor
    static func sampleDataForContactCryptoId(_ contactCryptoId: ObvCryptoId) -> Self {
        switch contactCryptoId {
        case ObvCryptoId.sampleDatasForContactCryptoId[0]:
            return .init(foreground: .blue, background: .yellow)
        case ObvCryptoId.sampleDatasForContactCryptoId[1]:
            return .init(foreground: .red, background: .yellow)
        case ObvCryptoId.sampleDatasForContactCryptoId[2]:
            return .init(foreground: .cyan, background: .red)
        case ObvCryptoId.sampleDatasForContactCryptoId[3]:
            return .init(foreground: .purple, background: .cyan)
        case ObvCryptoId.sampleDatasForContactCryptoId[4]:
            return .init(foreground: .systemPink, background: .purple)
        case ObvCryptoId.sampleDatasForContactCryptoId[5]:
            return .init(foreground: .blue, background: .systemPink)
        case ObvCryptoId.sampleDatasForContactCryptoId[6]:
            return .init(foreground: .green, background: .yellow)
        case ObvCryptoId.sampleDatasForContactCryptoId[7]:
            return .init(foreground: .white, background: .green)
        case ObvCryptoId.sampleDatasForContactCryptoId[8]:
            return .init(foreground: .blue, background: .white)
        case ObvCryptoId.sampleDatasForContactCryptoId[9]:
            return .init(foreground: .blue, background: .yellow)
        default:
            return .init(foreground: .systemPink, background: .systemCyan)
        }
    }

}


extension URL {
    
    @MainActor
    static func samplePhotoURLForOwnedCryptoId(_ ownedCryptoId: ObvCryptoId) -> Self? {
        switch ownedCryptoId {
        case ObvCryptoId.sampleDatasForOwnedCryptoId:
            return URL(string: "https://dev.olvid.io/avatar00")!
        default:
            assertionFailure()
            return nil
        }
    }
    
    @MainActor
    static func samplePhotoURLForContactCryptoId(_ contactCryptoId: ObvCryptoId) -> Self? {
        switch contactCryptoId {
        case ObvCryptoId.sampleDatasForContactCryptoId[0]:
            return URL(string: "https://dev.olvid.io/avatar00")!
        case ObvCryptoId.sampleDatasForContactCryptoId[1]:
            return URL(string: "https://dev.olvid.io/avatar01")!
        case ObvCryptoId.sampleDatasForContactCryptoId[2]:
            return URL(string: "https://dev.olvid.io/avatar02")!
        case ObvCryptoId.sampleDatasForContactCryptoId[3]:
            return URL(string: "https://dev.olvid.io/avatar03")!
        case ObvCryptoId.sampleDatasForContactCryptoId[4]:
            return URL(string: "https://dev.olvid.io/avatar04")!
        case ObvCryptoId.sampleDatasForContactCryptoId[5]:
            return URL(string: "https://dev.olvid.io/avatar05")!
        case ObvCryptoId.sampleDatasForContactCryptoId[6]:
            return URL(string: "https://dev.olvid.io/avatar06")!
        case ObvCryptoId.sampleDatasForContactCryptoId[7]:
            return URL(string: "https://dev.olvid.io/avatar07")!
        case ObvCryptoId.sampleDatasForContactCryptoId[8]:
            return URL(string: "https://dev.olvid.io/avatar08")!
        case ObvCryptoId.sampleDatasForContactCryptoId[9]:
            return URL(string: "https://dev.olvid.io/avatar09")!
        default:
            return nil
        }
    }

}


extension UIImage {
    
    @MainActor
    static func sampleImageForURL(_ url: URL) -> UIImage? {
        let imageName = url.lastPathComponent
        print(imageName)
        return UIImage(named: imageName, in: ObvSingleDiscussionResources.bundle, compatibleWith: nil)
    }
    
}


extension Character {
    
    @MainActor
    static func sampleAvatarCharacterForOwnedCryptoId(_ ownedCryptoId: ObvCryptoId) -> Self {
        switch ownedCryptoId {
        case ObvCryptoId.sampleDatasForOwnedCryptoId:
            return "A"
        default:
            assertionFailure()
            return "Z"
        }
    }
    
    @MainActor
    static func sampleAvatarCharacterForContactCryptoId(_ contactCryptoId: ObvCryptoId) -> Self {
        switch contactCryptoId {
        case ObvCryptoId.sampleDatasForContactCryptoId[0]:
            return "B"
        case ObvCryptoId.sampleDatasForContactCryptoId[1]:
            return "C"
        case ObvCryptoId.sampleDatasForContactCryptoId[2]:
            return "D"
        case ObvCryptoId.sampleDatasForContactCryptoId[3]:
            return "E"
        case ObvCryptoId.sampleDatasForContactCryptoId[4]:
            return "F"
        case ObvCryptoId.sampleDatasForContactCryptoId[5]:
            return "G"
        case ObvCryptoId.sampleDatasForContactCryptoId[6]:
            return "H"
        case ObvCryptoId.sampleDatasForContactCryptoId[7]:
            return "I"
        case ObvCryptoId.sampleDatasForContactCryptoId[8]:
            return "J"
        case ObvCryptoId.sampleDatasForContactCryptoId[9]:
            return "K"
        default:
            return "Z"
        }
    }

}


extension ObvAvatarViewModel {
    
    @MainActor
    static func sampleDataForOwnedCryptoId(_ ownedCryptoId: ObvCryptoId) -> Self {
        .init(characterOrIcon: .character(.sampleAvatarCharacterForOwnedCryptoId(ownedCryptoId)),
              colors: Colors.sampleDataForOwnedCryptoId(ownedCryptoId),
              photoURL: URL.samplePhotoURLForOwnedCryptoId(ownedCryptoId))
    }
    
    @MainActor
    static func sampleDataForContactCryptoId(_ contactCryptoId: ObvCryptoId) -> Self {
        .init(characterOrIcon: .character(.sampleAvatarCharacterForContactCryptoId(contactCryptoId)),
              colors: Colors.sampleDataForContactCryptoId(contactCryptoId),
              photoURL: URL.samplePhotoURLForContactCryptoId(contactCryptoId))
    }
    
}


extension String {
    
    @MainActor
    static func sampleDisplayNameForOwnedCryptoId(_ ownedCryptoId: ObvCryptoId) -> Self {
        switch ownedCryptoId {
        case ObvCryptoId.sampleDatasForOwnedCryptoId:
            return "You"
        default:
            assertionFailure()
            return "None None"
        }
    }
    
    @MainActor
    static func sampleDisplayNameForContactCryptoId(_ contactCryptoId: ObvCryptoId) -> Self {
        switch contactCryptoId {
        case ObvCryptoId.sampleDatasForContactCryptoId[0]:
            return "Bastian Smith"
        case ObvCryptoId.sampleDatasForContactCryptoId[1]:
            return "Calanthe Sanchez"
        case ObvCryptoId.sampleDatasForContactCryptoId[2]:
            return "Diana Ramirez"
        case ObvCryptoId.sampleDatasForContactCryptoId[3]:
            return "Elowen Robinson"
        case ObvCryptoId.sampleDatasForContactCryptoId[4]:
            return "Frank Young"
        case ObvCryptoId.sampleDatasForContactCryptoId[5]:
            return "Gideon Wright"
        case ObvCryptoId.sampleDatasForContactCryptoId[6]:
            return "Hannah Mitchell"
        case ObvCryptoId.sampleDatasForContactCryptoId[7]:
            return "Isolde Stewart"
        case ObvCryptoId.sampleDatasForContactCryptoId[8]:
            return "Jack Gutierrez"
        case ObvCryptoId.sampleDatasForContactCryptoId[9]:
            return "Kate Castillo"
        default:
            return "Zoe Guolp"
        }
    }

}


extension Date {
    
    @MainActor
    static func sampleDataForOwnedCryptoId(_ ownedCryptoId: ObvCryptoId) -> Self {
        switch ownedCryptoId {
        case ObvCryptoId.sampleDatasForOwnedCryptoId:
            return .now
        default:
            assertionFailure()
            return .now
        }
    }
    
    
    @MainActor
    static func sampleDataForContactCryptoId(_ contactCryptoId: ObvCryptoId) -> Self {
        guard let index = ObvCryptoId.sampleDatasForContactCryptoId.firstIndex(of: contactCryptoId) else {
            assertionFailure()
            return .now
        }
        return Date.now.addingTimeInterval(.init(hours: -index))
    }
    
}


extension String {
    
    @MainActor
    static func samplePositionAtCompanyForContactCryptoId(_ contactCryptoId: ObvCryptoId) -> Self {
        return "Position @ Company"
    }

}


extension Character {
    
    @MainActor
    static func sampleReactionForOwnedCryptoId(_ ownedCryptoId: ObvCryptoId) -> Self {
        switch ownedCryptoId {
        case ObvCryptoId.sampleDatasForOwnedCryptoId:
            return "😅"
        default:
            assertionFailure()
            return "-"
        }
    }

    
    @MainActor
    static func sampleReactionForContactCryptoId(_ contactCryptoId: ObvCryptoId) -> Self {
        switch contactCryptoId {
        case ObvCryptoId.sampleDatasForContactCryptoId[0]:
            return "😅"
        case ObvCryptoId.sampleDatasForContactCryptoId[1]:
            return "😅"
        case ObvCryptoId.sampleDatasForContactCryptoId[2]:
            return "😇"
        case ObvCryptoId.sampleDatasForContactCryptoId[3]:
            return "🎉"
        case ObvCryptoId.sampleDatasForContactCryptoId[4]:
            return "❤️"
        case ObvCryptoId.sampleDatasForContactCryptoId[5]:
            return "😉"
        case ObvCryptoId.sampleDatasForContactCryptoId[6]:
            return "😇"
        case ObvCryptoId.sampleDatasForContactCryptoId[7]:
            return "😇"
        case ObvCryptoId.sampleDatasForContactCryptoId[8]:
            return "🙌"
        case ObvCryptoId.sampleDatasForContactCryptoId[9]:
            return "☝️"
        default:
            return "😈"
        }
    }
    
}


extension ReactionCellViewModel {
    
    @MainActor
    static func sampleDataForOwnedCryptoId(_ ownedCryptoId: ObvCryptoId) -> Self {
        .init(avatar: .sampleDataForOwnedCryptoId(ownedCryptoId),
              displayName: .sampleDisplayNameForOwnedCryptoId(ownedCryptoId),
              date: .sampleDataForOwnedCryptoId(ownedCryptoId),
              positionAndCompany: nil,
              reaction: .sampleReactionForOwnedCryptoId(ownedCryptoId),
              isOwnReaction: true,
              reactionIsPartOfPreferedReactions: false)
    }

    
    @MainActor
    static func sampleDataForContactCryptoId(_ contactCryptoId: ObvCryptoId) -> Self {
        .init(avatar: .sampleDataForContactCryptoId(contactCryptoId),
              displayName: .sampleDisplayNameForContactCryptoId(contactCryptoId),
              date: .sampleDataForContactCryptoId(contactCryptoId),
              positionAndCompany: .samplePositionAtCompanyForContactCryptoId(contactCryptoId),
              reaction: .sampleReactionForContactCryptoId(contactCryptoId),
              isOwnReaction: false,
              reactionIsPartOfPreferedReactions: true)
    }
    
}


extension ObvMessageReactionsViewModel.ReactionIdentifier {
    
    @MainActor
    static let sampleData: [Self] = {
        let forOwnedCryptoId: [Self] = [
            .forPreviews(ObvCryptoId.sampleDatasForOwnedCryptoId),
        ]
        let forContacts: [Self] = ObvCryptoId.sampleDatasForContactCryptoId.map({ .forPreviews($0) })
        return forOwnedCryptoId + forContacts
    }()
    
}


extension ObvMessageReactionsViewModel {
    
    @MainActor
    static var sampleData: Self {
        .init(reactionsIdentifiers: ObvMessageReactionsViewModel.ReactionIdentifier.sampleData)
    }
    
}

#endif
