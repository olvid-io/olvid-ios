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

import SwiftUI
import ObvTypes
import ObvAppTypes
import ObvDesignSystem
import ObvPollFeature


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


extension ObvDiscussionIdentifier {

    @MainActor
    static let sampleData: Self = .oneToOne(id: .init(
        contactCryptoId: ObvCryptoId.sampleDatasForContactCryptoId[0],
        ownedCryptoId: ObvCryptoId.sampleDatasForOwnedCryptoId))

}


extension SingleDiscussionView.CellIdentifier {

    @MainActor
    static let sampleData: [Self] = (0..<25).map { _ in .forPreview(UUID()) }

}


extension SingleDiscussionView.Model {

    @MainActor
    static var sampleData: Self {
        let cellIdentifiers = SingleDiscussionView.CellIdentifier.sampleData
        let lastCellModel = cellIdentifiers.last.flatMap({ SingleDiscussionCellView.Model.sampleDataForCellIdentifier[$0] })
        // The marker speaks for the last five messages, so that a preview shows it and what surrounds it. All five are named, as the screen is given them, so that
        // its label counts what is there rather than repeating a number.
        let theLastFive = Set(cellIdentifiers.suffix(5))
        return .init(cellIdentifiers: cellIdentifiers,
                     lastCellModel: lastCellModel,
                     newMessages: theLastFive.isEmpty ? nil : .init(theOnesThatCount: theLastFive))
    }

}


extension SingleDiscussionView.InitialValues {

    /// Seeds the last few cells only, as the real data source does, so that a preview shows both the seeded cells and the redacted skeletons of the
    /// cells left to the stream.
    @MainActor
    static var sampleData: Self {
        let seededIdentifiers = SingleDiscussionView.CellIdentifier.sampleData.suffix(10)
        let cellModels = SingleDiscussionCellView.Model.sampleDataForCellIdentifier
            .filter({ seededIdentifiers.contains($0.key) })
        // The marker is no longer here: it is streamed with the identifiers since Step 53 — see `SingleDiscussionView.Model.sampleData`.
        return .init(cellModels: cellModels,
                     sentenceSayingTheDiscussionIsEndToEndEncrypted: "Messages are protected with end-to-end authentication and end-to-end encryption.",
                     header: .sampleData,
                     // On in previews, where the effect is worth looking at — and a preview is not what its cost has to be judged from.
                     sentBubbleHueVariesWithScroll: true,
                     elasticScrolling: true)
    }

}


extension DiscussionHeader {

    /// A one-to-one discussion: a contact's name, their position at company, and their picture. Active, callable, unmuted — so the bar shows the ellipsis and no
    /// moon.
    @MainActor
    static var sampleData: Self {
        .init(title: "Alice Bourgeois",
              subtitle: "CTO at Olvid",
              avatar: .sampleDataForContactCryptoId(ObvCryptoId.sampleDatasForContactCryptoId[0]),
              isActive: true,
              isCallAvailable: true,
              theReaderCanWriteHere: true,
              mute: nil)
    }

    /// The same discussion after the reader has renamed the contact, so that a preview shows the header **following** rather than being read once.
    @MainActor
    static var sampleDataAfterARename: Self {
        .init(title: "Alice B.",
              subtitle: "CTO at Olvid",
              avatar: .sampleDataForContactCryptoId(ObvCryptoId.sampleDatasForContactCryptoId[0]),
              isActive: true,
              isCallAvailable: true,
              theReaderCanWriteHere: true,
              mute: nil)
    }

    /// A discussion with nothing to say about itself, which must draw one line and not a blank second one.
    @MainActor
    static var sampleDataWithoutSubtitle: Self {
        .init(title: "Alice Bourgeois",
              subtitle: "",
              avatar: .sampleDataForContactCryptoId(ObvCryptoId.sampleDatasForContactCryptoId[0]),
              isActive: true,
              isCallAvailable: true,
              theReaderCanWriteHere: true,
              mute: nil)
    }

    /// A muted discussion, so that a preview shows the moon inboard of the ellipsis and the sentence at the head of its menu. The mute ends soon, so that the moon
    /// can be watched taking itself away.
    @MainActor
    static var sampleDataMuted: Self {
        .init(title: "Alice Bourgeois",
              subtitle: "CTO at Olvid",
              avatar: .sampleDataForContactCryptoId(ObvCryptoId.sampleDatasForContactCryptoId[0]),
              isActive: true,
              isCallAvailable: true,
              theReaderCanWriteHere: true,
              mute: .init(endDate: Date.now.addingTimeInterval(10),
                          sentence: "New message notifications muted until in 10 seconds."))
    }

    /// A locked discussion: a padlock, its own title, no call, **no ellipsis at all**, and — Step 51 — **no composition bar**.
    @MainActor
    static var sampleDataLocked: Self {
        .init(title: "A locked discussion",
              subtitle: "",
              avatar: .init(characterOrIcon: .icon(.lock(.fill, .none)),
                            colors: .init(foreground: .secondaryLabel, background: .secondarySystemBackground),
                            photoURL: nil),
              isActive: false,
              isCallAvailable: false,
              theReaderCanWriteHere: false,
              mute: nil)
    }

}


extension String {

    @MainActor
    static let sampleMessageBodies: [Self] = [
        "Hey! Are we still on for tomorrow?",
        "Yes, 6pm works for me.",
        "I just pushed the branch, let me know what you think.",
        // Markdown, since step 15: a preview has to show that **bold** is bold and that a link is a link rather than a row of asterisks.
        "It is **done**, and the notes are *here*: https://example.org/the-notes",
        "This is a somewhat longer message, written to check that a bubble wraps over several lines the way it should, and that nothing overflows.",
        "👍",
        "Sorry, I missed your call.",
        // Either side of the rule that shows a body of nothing but emoji as the emoji alone: three are shown large and without a bubble, four go back into one.
        "🎉🥳🎈",
        "🎉🥳🎈🎊",
    ]

}


extension AttributedString {

    /// A sample body, parsed as markdown exactly as a real one is — so that a preview shows what the reader will see rather than what was typed.
    ///
    /// The app builds a real body from the message's own mentions and intents; this only has to produce the same *kind* of value.
    @MainActor
    static func sampleMessageBody(forMessageAtIndex index: Int) -> Self {
        let markdown = String.sampleMessageBodies[index % String.sampleMessageBodies.count]
        return (try? AttributedString(markdown: markdown)) ?? AttributedString(markdown)
    }

}


extension CGImage {

    /// A plain colour at the size asked for, so that a preview can show the placeholder of an attachment giving way to an image without needing a file
    /// anywhere. Core Graphics only, as everything that produces an image for this screen must be.
    /// A stand-in for a map that is *placed* by its coordinate, so that a preview can show a bubble following someone who moves.
    ///
    /// It has to depend on the place, or a preview shows nothing of Step 9d: the flat rectangle of ``sampleImage(pixelSize:)`` is the same picture wherever the sender
    /// goes, so a coordinate drifting behind it looks exactly like a coordinate standing still. A grid whose lines are drawn *from* the coordinate pans as the place
    /// does, which is what a map would do.
    static func sampleMapImage(pixelSize: CGSize, centeredOn coordinate: LocationCoordinate) -> CGImage? {
        let width = Int(pixelSize.width)
        let height = Int(pixelSize.height)
        guard width > 0, height > 0 else { return nil }
        guard let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }

        context.setFillColor(red: 0.85, green: 0.87, blue: 0.82, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // The zoom of the real bubble: 0.002° of latitude, about 223m, across the whole square. So a metre of movement is a little over a pixel of pan.
        let pixelsPerMetre = pixelSize.width / 223.0
        let metresPerDegreeOfLatitude = 111_320.0
        let spacing = pixelSize.width / 5.0
        let phaseY = (coordinate.latitude * metresPerDegreeOfLatitude * pixelsPerMetre).truncatingRemainder(dividingBy: Double(spacing))
        let phaseX = (coordinate.longitude * metresPerDegreeOfLatitude * pixelsPerMetre).truncatingRemainder(dividingBy: Double(spacing))

        context.setStrokeColor(red: 0.65, green: 0.68, blue: 0.62, alpha: 1)
        context.setLineWidth(pixelSize.width / 100)
        var y = -spacing + CGFloat(phaseY)
        while y < pixelSize.height + spacing {
            context.move(to: .init(x: 0, y: y))
            context.addLine(to: .init(x: pixelSize.width, y: y))
            y += spacing
        }
        var x = -spacing + CGFloat(phaseX)
        while x < pixelSize.width + spacing {
            context.move(to: .init(x: x, y: 0))
            context.addLine(to: .init(x: x, y: pixelSize.height))
            x += spacing
        }
        context.strokePath()

        return context.makeImage()
    }


    /// One frame of a sample animation: a square walking left to right across a coloured background, so that a preview of a GIF is visibly moving and it is
    /// visible *which* frame is on screen — a pacing mistake shows up as a stutter rather than as nothing at all.
    static func sampleAnimationFrame(pixelSize: CGSize, indexOfTheFrame: Int, numberOfFrames: Int) -> CGImage? {
        let width = Int(pixelSize.width)
        let height = Int(pixelSize.height)
        guard width > 0, height > 0, numberOfFrames > 0 else { return nil }
        guard let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(red: 0.16, green: 0.20, blue: 0.28, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let side = CGFloat(min(width, height)) / 4
        let travel = CGFloat(width) - side
        let progress = CGFloat(indexOfTheFrame) / CGFloat(numberOfFrames)
        context.setFillColor(red: 0.98, green: 0.75, blue: 0.18, alpha: 1)
        context.fill(CGRect(x: travel * progress, y: (CGFloat(height) - side) / 2, width: side, height: side))
        return context.makeImage()
    }


    static func sampleImage(pixelSize: CGSize) -> CGImage? {
        let width = Int(pixelSize.width)
        let height = Int(pixelSize.height)
        guard width > 0, height > 0 else { return nil }
        guard let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(red: 0.24, green: 0.58, blue: 0.71, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

}


extension MessageAttachment {

    /// Sample messages carry zero to five images, so that a preview shows every shape the grid takes: none, one alone, a single row, a row and a wide tile
    /// closing it, two rows, and two rows with a wide tile.
    static func sampleImages(forMessageAtIndex index: Int) -> [Self] {
        let numberOfImages = index % 6
        return (0..<numberOfImages).map { indexOfTheImage in
            .init(identifier: .forPreview(UUID()),
                  sha256: Data([UInt8(index), UInt8(indexOfTheImage)]),
                  index: indexOfTheImage,
                  fileName: "photo-\(indexOfTheImage).jpeg",
                  fileSize: 1_234_567,
                  uti: "public.jpeg")
        }
    }

    /// A file that is **already here**, which the previews' data source answers for at once instead of offering it to be downloaded.
    ///
    /// It exists for the picture of a reply header. Every other attachment in a preview starts out waiting to be asked for, so that the control and its giving way to
    /// a picture can be seen — but a reply header shows no control, a quotation being inert, so nothing there could ever ask, and its picture would stay a grey square
    /// for as long as the preview lived. Recognised by its sha256, which is what an image is cached under.
    @MainActor
    static let sampleFileAlreadyHere: Self = .init(identifier: .forPreview(UUID()),
                                                   sha256: sha256OfTheSampleFileAlreadyHere,
                                                   index: 0,
                                                   fileName: "Photo.png",
                                                   fileSize: 3_456_789,
                                                   uti: "public.png")

    static let sha256OfTheSampleFileAlreadyHere = Data([200, 201])


    /// Every third sample message carries a document, so that a preview appears beside messages that have none.
    static func sampleDocument(forMessageAtIndex index: Int) -> Self? {
        guard index % 3 == 0 else { return nil }
        return .init(identifier: .forPreview(UUID()),
                     sha256: Data([UInt8(index), 42]),
                     index: 0,
                     fileName: "Minutes of the meeting of the seventeenth of March.pdf",
                     fileSize: 2_345_678,
                     uti: "com.adobe.pdf")
    }

    /// Every fourth sample message carries a voice note, so that a player appears beside messages that have none.
    static func sampleAudio(forMessageAtIndex index: Int) -> Self? {
        guard index % 4 == 1 else { return nil }
        return .init(identifier: .forPreview(UUID()),
                     sha256: Data([UInt8(index), 7]),
                     index: 0,
                     fileName: "recording.m4a",
                     fileSize: 234_567,
                     uti: "public.mpeg-4-audio")
    }

    /// Sample messages carry zero to two cards, of kinds that read differently: a long filename that has to truncate, and a short one that does not.
    static func sampleCards(forMessageAtIndex index: Int) -> [Self] {
        let kinds: [(fileName: String, fileSize: Int, uti: String)] = [
            ("archive.zip", 2_345_678, "public.zip-archive"),
            ("holiday.mov", 87_654_321, "com.apple.quicktime-movie"),
        ]
        return (0..<(index % 3)).map { indexOfTheCard in
            let kind = kinds[indexOfTheCard % kinds.count]
            return .init(identifier: .forPreview(UUID()),
                         sha256: Data([UInt8(index), UInt8(200 + indexOfTheCard)]),
                         index: indexOfTheCard,
                         fileName: kind.fileName,
                         fileSize: kind.fileSize,
                         uti: kind.uti)
        }
    }

}


extension LinkPreviewInMessage {

    /// Every fifth sample message renders a link, so that a preview shows both routes a preview arrives by, and messages that have neither: one message in ten
    /// carries a preview its sender attached, and one in ten a link this device would go and fetch one for.
    static func sample(forMessageAtIndex index: Int) -> Self? {
        switch index % 10 {
        case 2:
            // With its shape, as an attached preview whose file has arrived always has: so a preview shows the card at its true height from the first frame, and
            // only the picture inside it appears a moment later.
            return .attached(.init(identifier: .forPreview(UUID()),
                                   sha256: Data([UInt8(index), 99]),
                                   index: 0,
                                   fileName: "https://example.org/a-page",
                                   fileSize: 12_345,
                                   uti: "olvid.link-preview"),
                             shape: .init(title: "A page with a rather long title, long enough to run onto a second line",
                                          desc: "What the page says of itself, which is usually a sentence or two and sometimes, on the sites that are given the whole of this space, a good deal more than that.",
                                          domain: "example.org",
                                          url: URL(string: "https://example.org/a-page"),
                                          showsTheWholeDescription: false,
                                          picture: .large(aspectRatio: 2)))
        case 7:
            return .toBeFetched(url: URL(string: "https://example.org/another-page")!)
        default:
            return nil
        }
    }

}


extension GifInMessage {

    /// Every seventh sample message carries an animated image, and the three that appear cover the three shapes worth looking at: a wide canvas, a tall one, and
    /// a GIF whose file is not here — the last being the only case that occupies 200×150 rather than 241pt on its longer side.
    static func sample(forMessageAtIndex index: Int) -> Self? {
        let canvasSize: CGSize?
        switch index % 21 {
        case 3: canvasSize = CGSize(width: 480, height: 270)
        case 10: canvasSize = CGSize(width: 240, height: 320)
        case 17: canvasSize = nil
        default: return nil
        }
        return .init(attachment: .init(identifier: .forPreview(UUID()),
                                       sha256: Data([UInt8(index), 77]),
                                       index: 0,
                                       fileName: "animation.gif",
                                       fileSize: 456_789,
                                       uti: "com.compuserve.gif"),
                     canvasSize: canvasSize)
    }

}


extension LocationInMessage {

    /// One sample message in five is a place, so that a preview shows the square among the ordinary messages it has to sit beside: a location sent once, with its
    /// pin and an address long enough to take two lines; someone sharing theirs, with their avatar and a countdown; and sharing that is over, with the panel that
    /// says so — whose wording depends on the cell it is in, so it reads one way in the sent preview and another in the received one.
    @MainActor
    static func sample(forMessageAtIndex index: Int) -> Self? {
        switch index % 5 {
        case 0 where index > 0:
            return .init(identifier: .forPreview(UUID()),
                         locationIdentifier: nil,
                         kind: .ended,
                         coordinate: nil,
                         isOwnSharingFromThisDevice: false,
                         sharer: .sampleDataForContactCryptoId(ObvCryptoId.sampleDatasForContactCryptoId[index % ObvCryptoId.sampleDatasForContactCryptoId.count]))
        case 1:
            return .init(identifier: .forPreview(UUID()),
                         locationIdentifier: .forPreview(UUID()),
                         kind: .oneShot,
                         coordinate: .init(latitude: 48.8566, longitude: 2.3522),
                         isOwnSharingFromThisDevice: false,
                         sharer: nil)
        case 3:
            return .init(identifier: .forPreview(UUID()),
                         locationIdentifier: .forPreview(UUID()),
                         kind: .continuous,
                         coordinate: .init(latitude: 45.7640, longitude: 4.8357),
                         // So that a preview shows the countdown, which only the reader's own sharing from this device is given.
                         isOwnSharingFromThisDevice: true,
                         sharer: .sampleDataForContactCryptoId(ObvCryptoId.sampleDatasForContactCryptoId[index % ObvCryptoId.sampleDatasForContactCryptoId.count]))
        default:
            return nil
        }
    }

}


extension PollInMessage {

    /// One sample message in seven asks a poll, so that a preview shows the bubble among the ordinary messages it sits beside.
    static func sample(forMessageAtIndex index: Int) -> Self? {
        guard index % 7 == 4 else { return nil }
        // The shape a preview shows redacted before its votes arrive — a question long enough to wrap, an answer long enough to wrap, and an expiry, those being
        // the three things that make a poll's height something other than a constant.
        return .init(identifier: .forPreview(UUID()),
                     pollIdentifier: .forPreview(UUID()),
                     shape: .init(question: "Which day suits everyone for the retrospective, given that the room is only free in the afternoons?",
                                  multipleChoice: true,
                                  candidates: [
                                    .init(uuid: UUID(), text: "Tuesday"),
                                    .init(uuid: UUID(), text: "Wednesday, but only after the standup has finished"),
                                    .init(uuid: UUID(), text: "Thursday"),
                                  ],
                                  expirationDate: Date.now.addingTimeInterval(3 * 86_400)))
    }

}


extension TapToRead {

    /// One sample message in eleven has to be asked for, half of them with something written and half with only a photograph — the second being the case that shows
    /// no bubble at all, and whose covered square is the only thing there is to tap.
    @MainActor
    static func sample(forMessageAtIndex index: Int) -> Self? {
        switch index % 11 {
        case 5:
            return .init(identifier: .forPreview(UUID()),
                         showsTheBubble: true,
                         covered: .init(textBody: nil, linkPreview: nil, gif: nil, images: [], video: nil, document: nil, audio: nil, cards: []))
        case 9:
            return .init(identifier: .forPreview(UUID()),
                         showsTheBubble: false,
                         covered: .init(textBody: nil,
                                        linkPreview: nil,
                                        gif: nil,
                                        images: MessageAttachment.sampleImages(forMessageAtIndex: 1),
                                        video: nil,
                                        document: nil,
                                        audio: nil,
                                        cards: []))
        default:
            return nil
        }
    }

}


extension WipedMessage {

    /// One sample message in thirteen is gone, alternating between the two sentences a reader can actually meet — the third, a deleter with no name, being the same
    /// view with nothing to interpolate.
    static func sample(forMessageAtIndex index: Int) -> Self? {
        switch index % 13 {
        case 6: return .byTheExpiryOfItsOwnVisibility
        case 11: return .byAContact(named: "Alice")
        default: return nil
        }
    }

}


extension MessageContent {

    /// What a sample message shows: a place, when the index says so, and otherwise its text and whatever is attached to it.
    @MainActor
    static func sample(forMessageAtIndex index: Int) -> Self {
        if let location = LocationInMessage.sample(forMessageAtIndex: index) {
            return .location(location)
        }
        if let poll = PollInMessage.sample(forMessageAtIndex: index) {
            return .poll(poll)
        }
        if let tapToRead = TapToRead.sample(forMessageAtIndex: index) {
            return .tapToRead(tapToRead)
        }
        if let wiped = WipedMessage.sample(forMessageAtIndex: index) {
            return .wiped(wiped)
        }
        return .ordinary(.init(textBody: AttributedString.sampleMessageBody(forMessageAtIndex: index),
                               linkPreview: LinkPreviewInMessage.sample(forMessageAtIndex: index),
                               gif: GifInMessage.sample(forMessageAtIndex: index),
                               images: MessageAttachment.sampleImages(forMessageAtIndex: index),
                               video: nil,
                               document: MessageAttachment.sampleDocument(forMessageAtIndex: index),
                               audio: MessageAttachment.sampleAudio(forMessageAtIndex: index),
                               cards: MessageAttachment.sampleCards(forMessageAtIndex: index)))
    }

}


extension MessageSender {

    /// The people a preview's group discussion is with, plus a contact since deleted — which is the one case whose name, colour and icon come from nowhere but the
    /// absence of a contact.
    @MainActor
    static let sampleData: [Self] = ObvCryptoId.sampleDatasForContactCryptoId.prefix(4).map { contactCryptoId in
        .init(name: .sampleDisplayNameForContactCryptoId(contactCryptoId),
              nameColor: .sampleNameColorForContactCryptoId(contactCryptoId),
              avatar: .sampleDataForContactCryptoId(contactCryptoId),
              contactIdentifier: .init(contactCryptoId: contactCryptoId, ownedCryptoId: .sampleDatasForOwnedCryptoId))
    } + [
        .init(name: "A (now deleted) contact", nameColor: .secondary, avatar: .sampleDataForADeletedContact, contactIdentifier: nil),
    ]


    /// Who sent the sample message at this index, in runs of two or three, so that a preview shows a name once above a run and the column of the picture kept empty
    /// under it — the two halves of Step 16 that a single message could not show.
    ///
    /// A run is broken by a *day* as well as by another sender, which is why this reads ``dateSeparator(forMessageAtIndex:)``: the legacy screen compares within one
    /// section only, so the first message of a day names its sender again whoever sent the one before.
    @MainActor
    static func sample(forMessageAtIndex index: Int) -> SenderOfAMessage {
        let sender = sampleData[(index / 3) % sampleData.count]
        guard index > 0, Date.dateSeparator(forMessageAtIndex: index) == nil, !index.isMultiple(of: 3) else {
            return .shown(sender)
        }
        return .withinARunOfTheirMessages
    }

}


extension Color {

    /// The colour a sample sender's name is drawn in. A real one comes from the sender's cryptographic identity, and is the colour their picture is drawn in too;
    /// a preview only has to show that the two agree and that two people differ, so these mirror the foreground colours of
    /// ``ObvAvatarViewModel/Colors/sampleDataForContactCryptoId(_:)``.
    @MainActor
    static func sampleNameColorForContactCryptoId(_ contactCryptoId: ObvCryptoId) -> Self {
        switch contactCryptoId {
        case ObvCryptoId.sampleDatasForContactCryptoId[0]: return .blue
        case ObvCryptoId.sampleDatasForContactCryptoId[1]: return .red
        case ObvCryptoId.sampleDatasForContactCryptoId[2]: return .cyan
        case ObvCryptoId.sampleDatasForContactCryptoId[3]: return .purple
        default: return .pink
        }
    }

}


extension ObvAvatarViewModel {

    /// The picture of a contact who is no longer one: the icon and the two colours `CircledInitialsConfiguration.icon` gives, which is what the app builds for them.
    @MainActor
    static let sampleDataForADeletedContact: Self = .init(characterOrIcon: .icon(.personFillXmark),
                                                          colors: .init(foreground: .secondaryLabel, background: .systemFill),
                                                          photoURL: nil)

}


extension MessageRepliedTo {

    /// Every shape a reply header takes: a contact's words, a contact's photograph quoted by its file name, the reader's own message, a contact who can no longer be
    /// found, one that was wiped, one deleted, and one that has yet to arrive.
    @MainActor
    static let sampleData: [Self] = [
        .init(identifier: .forPreview(UUID()),
              sender: .aContact(name: .sampleDisplayNameForContactCryptoId(ObvCryptoId.sampleDatasForContactCryptoId[0]),
                                color: .sampleNameColorForContactCryptoId(ObvCryptoId.sampleDatasForContactCryptoId[0])),
              whatItSays: .theseWords("I just pushed the branch, let me know what you think. It is the one with the fix for the layout, so it should be quick to read."),
              thumbnail: nil),
        .init(identifier: .forPreview(UUID()),
              sender: .aContact(name: .sampleDisplayNameForContactCryptoId(ObvCryptoId.sampleDatasForContactCryptoId[1]),
                                color: .sampleNameColorForContactCryptoId(ObvCryptoId.sampleDatasForContactCryptoId[1])),
              whatItSays: .theseWords("Photo.png"),
              // The one sample file a preview shows the picture of, for the reason ``MessageAttachment/sampleFileAlreadyHere`` gives.
              thumbnail: .sampleFileAlreadyHere),
        .init(identifier: .forPreview(UUID()),
              sender: .theReader(name: "You"),
              whatItSays: .theseWords("Yes, 6pm works for me."),
              thumbnail: nil),
        .init(identifier: .forPreview(UUID()),
              sender: .aContactNoLongerKnown(name: "A (now deleted) contact"),
              whatItSays: .theseWords("Sorry, I missed your call."),
              thumbnail: nil),
        .init(identifier: .forPreview(UUID()),
              sender: .aContact(name: .sampleDisplayNameForContactCryptoId(ObvCryptoId.sampleDatasForContactCryptoId[2]),
                                color: .sampleNameColorForContactCryptoId(ObvCryptoId.sampleDatasForContactCryptoId[2])),
              whatItSays: .itWasWipedBy(contactNamed: "Alice"),
              thumbnail: nil),
        .init(identifier: nil, sender: .nobody, whatItSays: .itWasDeleted, thumbnail: nil),
        .init(identifier: nil, sender: .nobody, whatItSays: .itIsNotHereYet, thumbnail: nil),
    ]


    /// One sample message in three answers another, so that a preview shows the header above a bubble, above a picture, and above the parts of a cell that come with
    /// it — a badge, a sender, a date separator.
    @MainActor
    static func sample(forMessageAtIndex index: Int) -> Self? {
        guard index % 3 == 1 else { return nil }
        return sampleData[(index / 3) % sampleData.count]
    }

}


extension Bool {

    /// Whether the sample message at this index was forwarded, one in seven being — enough that a preview shows the badge above a bubble, above a picture, and above a
    /// message that is nothing but a badge and a date.
    static func sampleIsForwarded(forMessageAtIndex index: Int) -> Self {
        index % 7 == 2
    }


    /// Whether the sample message at this index says it was edited, one in five saying so. The suppression rules are the data source's, so a preview only has to show
    /// the mark in the date row, beside the date and before the status of a message sent.
    static func sampleIsShownAsEdited(forMessageAtIndex index: Int) -> Self {
        index % 5 == 3
    }

}


extension Int {

    /// How many messages are missing above the sample message at this index — one at one index and several at another, so that a preview shows both plural forms of
    /// the sentence. Zero everywhere else, which is what keeps the bubble off every other cell.
    static func sampleMissedMessageCount(forMessageAtIndex index: Int) -> Self {
        switch index {
        case 2: return 1
        case 5: return 4
        default: return 0
        }
    }

}


extension Date {

    /// The day a sample message opens, one message in four opening one, so that a preview shows the separators and the wording of each of the four cases: today,
    /// yesterday, a day of this month, and a day of another year.
    @MainActor
    static func dateSeparator(forMessageAtIndex index: Int) -> Date? {
        switch index {
        case 0: return Date.now
        case 4: return Date.now.addingTimeInterval(-86_400)
        case 6: return Date.now.addingTimeInterval(-12 * 86_400)
        case 8: return Date.now.addingTimeInterval(-400 * 86_400)
        default: return nil
        }
    }

}


extension ReactionsOfAMessage {

    /// Every sample message may be reacted to, except one the reader has still to ask to see — which is the rule the app's data source applies, and the one branch
    /// the legacy received cell has for reactions.
    ///
    /// *How many* reactions each of them turns out to have is not decided here but by the preview data source, which answers from the identifier — see
    /// `SingleDiscussionCellViewDataSourceForPreviews.getAsyncStreamOfReactionsCountViewModel(messageIdentifier:)`. That is deliberate: it is the split this step is
    /// about, the model saying only that a message shows its reactions and the stream saying what they are.
    @MainActor
    static func sample(forMessageAtIndex index: Int) -> Self? {
        guard TapToRead.sample(forMessageAtIndex: index) == nil else { return nil }
        return .init(identifier: .forPreview(UUID()))
    }

}


extension SentMessageCellView.Model {

    /// Covers every status indicator, including the case where no indicator is shown at all.
    @MainActor
    static let sampleStatusIcons: [StatusIcon] = [
        .custom(.checkmark),                 // sent
        .custom(.checkmarkCircle),           // fully delivered, not read
        .custom(.checkmarkCircleFill),       // fully delivered and fully read
        .custom(.checkmarkDoubleCircleFill), // fully delivered and fully read, several recipients
        .system(.exclamationmarkCircle),     // could not be sent to one or more recipients
        .none,                               // has no recipient
    ]

    @MainActor
    static let sampleData: [Self] = (0..<String.sampleMessageBodies.count).map { index in
        .init(content: .sample(forMessageAtIndex: index),
              statusIcon: sampleStatusIcons[index % sampleStatusIcons.count],
              timestamp: Date.now.addingTimeInterval(-Double(index) * 600),
              dateSeparator: Date.dateSeparator(forMessageAtIndex: index),
              isForwarded: .sampleIsForwarded(forMessageAtIndex: index),
              isShownAsEdited: .sampleIsShownAsEdited(forMessageAtIndex: index),
              repliedTo: MessageRepliedTo.sample(forMessageAtIndex: index),
              reactions: ReactionsOfAMessage.sample(forMessageAtIndex: index),
              ephemerality: .sample(forMessageAtIndex: index))
    }

}


extension ReceivedMessageCellView.Model {

    @MainActor
    static let sampleData: [Self] = (0..<String.sampleMessageBodies.count).map { index in
        .init(content: .sample(forMessageAtIndex: index),
              timestamp: Date.now.addingTimeInterval(-Double(index) * 600),
              dateSeparator: Date.dateSeparator(forMessageAtIndex: index),
              sender: MessageSender.sample(forMessageAtIndex: index),
              isForwarded: .sampleIsForwarded(forMessageAtIndex: index),
              isShownAsEdited: .sampleIsShownAsEdited(forMessageAtIndex: index),
              missedMessageCount: .sampleMissedMessageCount(forMessageAtIndex: index),
              repliedTo: MessageRepliedTo.sample(forMessageAtIndex: index),
              reactions: ReactionsOfAMessage.sample(forMessageAtIndex: index),
              ephemerality: .sample(forMessageAtIndex: index))
    }


    /// The same messages in a discussion that names nobody, so that a preview shows what a one-to-one discussion looks like: no picture, no name, and no column kept
    /// for either.
    @MainActor
    static let sampleDataInAOneToOneDiscussion: [Self] = sampleData.map { model in
        .init(content: model.content,
              timestamp: model.timestamp,
              dateSeparator: model.dateSeparator,
              sender: .neverShown,
              isForwarded: model.isForwarded,
              isShownAsEdited: model.isShownAsEdited,
              missedMessageCount: model.missedMessageCount,
              repliedTo: model.repliedTo,
              reactions: model.reactions,
              ephemerality: model.ephemerality)
    }

}


extension TheEphemeralityOfAMessage {

    /// A handful of the sample messages are ephemeral, and each in a different way, so that a preview shows every state the countdown
    /// has: a flame, an eye counting visibility down, a timer counting existence down, and one with seconds left, which is the only
    /// state whose colour is red.
    ///
    /// **The messages still to be tapped are answered first, from `TapToRead`'s own sample** rather than from a cycle of this
    /// function's own. That is the one case ``WhatWillHappenWhenThisMessageIsRead`` appears in, and it is a fact about the *content*
    /// of a message: a `readingRequiresUserAction` landing on an index whose body is already readable would draw the terms of a tap
    /// beside a message there is nothing to tap.
    @MainActor
    static func sample(forMessageAtIndex index: Int) -> Self {
        if let tapToRead = TapToRead.sample(forMessageAtIndex: index) {
            // Two of the three shapes the chip comes in, one on each of the two tap-to-read samples: a message that burns when read
            // and says nothing about how long it lasts, and one that grants a minute and does not burn. The third — both at once —
            // is in this view's own preview.
            return tapToRead.showsTheBubble
            ? .init(readOnce: true, readingRequiresUserAction: true, visibilityDuration: nil, scheduledVisibilityDestructionDate: nil, scheduledExistenceDestructionDate: Date.now.addingTimeInterval(5 * 60))
            : .init(readOnce: false, readingRequiresUserAction: true, visibilityDuration: 60, scheduledVisibilityDestructionDate: nil, scheduledExistenceDestructionDate: nil)
        }
        switch index % 9 {
        case 1:
            return .init(readOnce: true, readingRequiresUserAction: false, visibilityDuration: nil, scheduledVisibilityDestructionDate: nil, scheduledExistenceDestructionDate: nil)
        case 3:
            return .init(readOnce: false, readingRequiresUserAction: false, visibilityDuration: 300, scheduledVisibilityDestructionDate: Date.now.addingTimeInterval(42), scheduledExistenceDestructionDate: nil)
        case 5:
            return .init(readOnce: false, readingRequiresUserAction: false, visibilityDuration: nil, scheduledVisibilityDestructionDate: nil, scheduledExistenceDestructionDate: Date.now.addingTimeInterval(3 * 3600))
        case 7:
            return .init(readOnce: false, readingRequiresUserAction: false, visibilityDuration: 86400, scheduledVisibilityDestructionDate: Date.now.addingTimeInterval(5 * 86400), scheduledExistenceDestructionDate: Date.now.addingTimeInterval(30 * 86400))
        default:
            return .none
        }
    }

}


extension SystemMessageCellView.Model {

    /// One of each colour, so that a preview shows what a reader can tell apart: something about a group, something to be careful about, something wrong, and a call.
    @MainActor
    static let sampleData: [Self] = [
        .init(text: "Alice joined the group.", tint: .green, timestamp: .now, dateSeparator: nil),
        .init(text: "The shared settings of this discussion were updated.", tint: .orange, timestamp: .now, dateSeparator: nil),
        .init(text: "This contact was revoked by the identity provider.", tint: .red, timestamp: .now, dateSeparator: nil),
        .init(text: "Missed call with Alice", tint: .purple, timestamp: .now, dateSeparator: nil),
        .init(text: "Messages are protected with end-to-end authentication and end-to-end encryption.", tint: .green, timestamp: nil, dateSeparator: nil),
    ]


    /// Every fifth sample cell says something about the discussion rather than showing a message, so that a preview of the whole screen shows them among the bubbles.
    @MainActor
    static func sample(forCellAtIndex index: Int) -> Self? {
        guard index % 5 == 3 else { return nil }
        return sampleData[(index / 5) % sampleData.count]
    }

}


extension SingleDiscussionCellView.Model {

    /// Alternates sent and received messages over the sample cell identifiers, so that a preview of the whole screen shows both kinds.
    @MainActor
    static let sampleDataForCellIdentifier: [SingleDiscussionView.CellIdentifier: Self] = {
        var result = [SingleDiscussionView.CellIdentifier: Self]()
        for (index, cellIdentifier) in SingleDiscussionView.CellIdentifier.sampleData.enumerated() {
            if let systemMessage = SystemMessageCellView.Model.sample(forCellAtIndex: index) {
                result[cellIdentifier] = .systemMessage(systemMessage)
            } else if index.isMultiple(of: 2) {
                let model = SentMessageCellView.Model.sampleData[index % SentMessageCellView.Model.sampleData.count]
                result[cellIdentifier] = .sentMessage(model)
            } else {
                let model = ReceivedMessageCellView.Model.sampleData[index % ReceivedMessageCellView.Model.sampleData.count]
                result[cellIdentifier] = .receivedMessage(model)
            }
        }
        return result
    }()

}

#endif
