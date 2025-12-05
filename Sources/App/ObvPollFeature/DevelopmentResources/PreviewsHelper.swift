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
import ObvCrypto
import ObvTypes
import ObvAppTypes
import ObvDesignSystem

extension UID {
    
    @MainActor
    static var sampleDatas: [UID] = [
        UID(uid: Data(repeating: 0x00, count: 32))!,
        UID(uid: Data(repeating: 0x01, count: 32))!,
        UID(uid: Data(repeating: 0x02, count: 32))!,
        UID(uid: Data(repeating: 0x03, count: 32))!,
        UID(uid: Data(repeating: 0x04, count: 32))!,
        UID(uid: Data(repeating: 0x05, count: 32))!,
    ]

}

extension ObvCryptoId {
    
    @MainActor
    static var sampleDatas: [Self] = [
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f0000b82ae0c57e570389cb03d5ad93dab4606bda7bbe01c09ce5e423094a8603a61e01693046e10e04606ef4461d31e1aa1819222a0a606a250e91749095a4410778c1")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f000009e171a9c73a0d6e9480b022154c83b13dfa8e4c99496c061c0c35b9b0432b3a014a5393f98a1aead77b813df0afee6b8af7e5f9a5aae6cb55fdb6bc5cc766f8da")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f00002d459c378a0bbc54c8be3e87e82d02347c046c4a50a6db25fe15751d8148671401054f3b14bbd7319a1f6d71746d6345332b92e193a9ea00880dd67b2f10352831")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f000089aebda5ddb3a59942d4fe6e00720b851af1c2d70b6e24e41ac8da94793a6eb70136a23bf11bcd1ccc244ab3477545cc5fee6c60c2b89b8ff2fb339f7ed2ff1f0a")!),
    ]
    
}

//extension ObvDiscussionIdentifier {
//    @MainActor
//    static var sampleDatas: [ObvDiscussionIdentifier] = [
//        .groupV2(id: ObvGroupV2Identifier.sampleDatas[0])
//        ]
//}
//
//extension ObvGroupV2Identifier {
//    @MainActor
//    static var sampleDatas: [Self] = [
//        .init(ownedCryptoId: ObvCryptoId.sampleDatas[0], identifier: ObvGroupV2.Identifier.sampleDatas[0])
//        ]
//}
//
//extension ObvGroupV2.Identifier {
//    
//    @MainActor
//    static var sampleDatas: [Self] = [
//        .init(groupUID: UID.sampleDatas[0], serverURL: URL(string: "https://olvid.io")!, category: .server)
//        ]
//    
//}

private extension ObvAvatarViewModel.Colors {
    
    @MainActor
    static var sampleDatas: [Self] = [
        .init(foreground: .systemBlue,
              background: .systemRed),
        .init(foreground: .systemPink,
              background: .systemCyan),
    ]
    
}

public extension ObvAvatarViewModel {
    
    @MainActor
    static var sampleDatas: [Self] = [
        .init(characterOrIcon: .character("A"),
              colors: Colors.sampleDatas[0],
              photoURL: URL.sampleDatas[0]),
        .init(characterOrIcon: .character("B"),
              colors: Colors.sampleDatas[0],
              photoURL: URL.sampleDatas[0]),
        .init(characterOrIcon: .character("C"),
              colors: Colors.sampleDatas[1],
              photoURL: URL.sampleDatas[0]),
        .init(characterOrIcon: .character("D"),
              colors: Colors.sampleDatas[1],
              photoURL: URL.sampleDatas[0]),
    ]
    
}

private extension URL {
    
    @MainActor
    static var sampleDatas: [Self] = [
        URL(string: "https://olvid.io/avatar00.png")!,
        URL(string: "https://olvid.io/avatar01.png")!,
        URL(string: "https://olvid.io/avatar02.png")!,
        URL(string: "https://olvid.io/avatar03.png")!,
        URL(string: "https://olvid.io/avatar04.png")!,
        URL(string: "https://olvid.io/avatar05.png")!,
    ]
    
}


extension PollVoteViewModel.VoteIdentifier {
    
    @MainActor
    static var sampleDatas: [Self] = [
        .forPreviews(UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))),
        .forPreviews(UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1))),
        .forPreviews(UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2))),
        .forPreviews(UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,3))),
    ]
    
}

extension PollVoteViewModel {
    
    @MainActor
    static func sampleDatasForIdentifier(_ voteIdentifier: PollVoteViewModel.VoteIdentifier) -> Self? {
        switch voteIdentifier {
        case PollVoteViewModel.VoteIdentifier.sampleDatas[0]:
            return .init(identifier: voteIdentifier, name: "Mathieu", timestamp: Date.now - (60 * 60 * 24 * 4.5), avatarModel: ObvAvatarViewModel.sampleDatas[0])
        case PollVoteViewModel.VoteIdentifier.sampleDatas[1]:
            return .init(identifier: voteIdentifier, name: "Robert", timestamp: Date.now - (60 * 60 * 24), avatarModel: ObvAvatarViewModel.sampleDatas[1])
        case PollVoteViewModel.VoteIdentifier.sampleDatas[2]:
            return .init(identifier: voteIdentifier, name: "Valentin", timestamp: Date.now - (60 * 60 * 24 * 2), avatarModel: ObvAvatarViewModel.sampleDatas[2])
        case PollVoteViewModel.VoteIdentifier.sampleDatas[3]:
            return .init(identifier: voteIdentifier, name: "Céline", timestamp: Date.now - (60), avatarModel: ObvAvatarViewModel.sampleDatas[3])
        default:
            assertionFailure()
            return nil
        }
    }
    
}


extension PollCandidateIdentifier {
    
    @MainActor
    static var sampleDatas: [Self] = [
        .forPreviews(pollIdentifier: .forPreviews, candidateUUID: UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))),
        .forPreviews(pollIdentifier: .forPreviews, candidateUUID: UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1))),
        .forPreviews(pollIdentifier: .forPreviews, candidateUUID: UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,2))),
        .forPreviews(pollIdentifier: .forPreviews, candidateUUID: UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,3))),
        .forPreviews(pollIdentifier: .forPreviews, candidateUUID: UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,4))),
        .forPreviews(pollIdentifier: .forPreviews, candidateUUID: UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,5))),
        .forPreviews(pollIdentifier: .forPreviews, candidateUUID: UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,6))),
        .forPreviews(pollIdentifier: .forPreviews, candidateUUID: UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,7))),
    ]
    
}

extension Int {
    
    private static let numberOfResponses: [Int] = [23, 0, 16, 3, 1, 12, 77, 7]
    
    fileprivate static func numberOfResponses(atIndex index: Int) -> Int {
        guard index < numberOfResponses.count else { return 0 }
        return Int.numberOfResponses[index]
    }
    
    fileprivate static let totalNumberOfResponses: Int = numberOfResponses.reduce(0, +)
    
}

extension PollViewCandidateModel {
    
    @MainActor
    static func sampleDatasForIdentifier(_ candidateIdentifier: PollCandidateIdentifier) -> Self? {
        switch candidateIdentifier {
        case PollCandidateIdentifier.sampleDatas[0]:
            return .init(identifier: candidateIdentifier,
                         text: "Reponse 0",
                         isVotedByOwnedIdentity: .no,
                         numberOfResponses: Int.numberOfResponses(atIndex: 0),
                         totalNumberOfResponses: Int.totalNumberOfResponses,
                         pollSortIndex: 0)
        case PollCandidateIdentifier.sampleDatas[1]:
            return .init(identifier: candidateIdentifier,
                         text: "Reponse 1",
                         isVotedByOwnedIdentity: .yes(avatarModelOfOwnedIdentity: ObvAvatarViewModel.sampleDatas[0]),
                         numberOfResponses: Int.numberOfResponses(atIndex: 1),
                         totalNumberOfResponses: Int.totalNumberOfResponses,
                         pollSortIndex: 1)
        case PollCandidateIdentifier.sampleDatas[2]:
            return .init(identifier: candidateIdentifier,
                         text: "Reponse 2",
                         isVotedByOwnedIdentity: .no,
                         numberOfResponses: Int.numberOfResponses(atIndex: 2),
                         totalNumberOfResponses: Int.totalNumberOfResponses,
                         pollSortIndex: 2)
        case PollCandidateIdentifier.sampleDatas[3]:
            return .init(identifier: candidateIdentifier,
                         text: "Reponse 3",
                         isVotedByOwnedIdentity: .no,
                         numberOfResponses: Int.numberOfResponses(atIndex: 3),
                         totalNumberOfResponses: Int.totalNumberOfResponses,
                         pollSortIndex: 3)
        case PollCandidateIdentifier.sampleDatas[4]:
            return .init(identifier: candidateIdentifier,
                         text: "Reponse 4",
                         isVotedByOwnedIdentity: .yes(avatarModelOfOwnedIdentity: ObvAvatarViewModel.sampleDatas[0]),
                         numberOfResponses: Int.numberOfResponses(atIndex: 4),
                         totalNumberOfResponses: Int.totalNumberOfResponses,
                         pollSortIndex: 4)
        case PollCandidateIdentifier.sampleDatas[5]:
            return .init(identifier: candidateIdentifier,
                         text: "Reponse 5",
                         isVotedByOwnedIdentity: .yes(avatarModelOfOwnedIdentity: ObvAvatarViewModel.sampleDatas[0]),
                         numberOfResponses: Int.numberOfResponses(atIndex: 5),
                         totalNumberOfResponses: Int.totalNumberOfResponses,
                         pollSortIndex: 5)
        case PollCandidateIdentifier.sampleDatas[6]:
            return .init(identifier: candidateIdentifier,
                         text: "Reponse 6",
                         isVotedByOwnedIdentity: .no,
                         numberOfResponses: Int.numberOfResponses(atIndex: 6),
                         totalNumberOfResponses: Int.totalNumberOfResponses,
                         pollSortIndex: 6)
        case PollCandidateIdentifier.sampleDatas[7]:
            return .init(identifier: candidateIdentifier,
                         text: "Reponse 7",
                         isVotedByOwnedIdentity: .no,
                         numberOfResponses: Int.numberOfResponses(atIndex: 7),
                         totalNumberOfResponses: Int.totalNumberOfResponses,
                         pollSortIndex: 7)
        default:
            assertionFailure()
            return nil
        }
    }
    
}


extension PollCandidateViewModel {
    
    @MainActor
    static var sampleData: Self = .init(
        candidateIdentifier: PollCandidateIdentifier.sampleDatas[0],
        identifiersOfVotes: PollVoteViewModel.VoteIdentifier.sampleDatas)
    
}


extension VoterWhoDidNotVoteYetViewModel.VoterIdentifier {
    
    @MainActor
    static var sampleDatas: [Self] = ObvCryptoId.sampleDatas.map({ .forPreviews(cryptoId: $0) })

}


extension VoterWhoDidNotVoteYetViewModel {
    
    
    @MainActor
    static func sampleDatasForIdentifier(_ identifier: VoterWhoDidNotVoteYetViewModel.VoterIdentifier) -> Self? {
        switch identifier {
        case VoterWhoDidNotVoteYetViewModel.VoterIdentifier.sampleDatas[0]:
            return .init(identifier: identifier, name: "Alice", avatarModel: ObvAvatarViewModel.sampleDatas[0])
        case VoterWhoDidNotVoteYetViewModel.VoterIdentifier.sampleDatas[1]:
            return .init(identifier: identifier, name: "Bob", avatarModel: ObvAvatarViewModel.sampleDatas[1])
        case VoterWhoDidNotVoteYetViewModel.VoterIdentifier.sampleDatas[2]:
            return .init(identifier: identifier, name: "Charlie", avatarModel: ObvAvatarViewModel.sampleDatas[2])
        case VoterWhoDidNotVoteYetViewModel.VoterIdentifier.sampleDatas[3]:
            return .init(identifier: identifier, name: "David", avatarModel: ObvAvatarViewModel.sampleDatas[3])
        default:
            return nil
        }
    }
    
}


extension PollIdentifier {
    
    @MainActor
    static var sampleDatas: Self = PollIdentifier.forPreviews

    
}

extension PollViewModel {
    
    @MainActor
    private static let sampleData: Self = PollViewModel(
        question: "The question",
        candidates: PollCandidateIdentifier.sampleDatas.compactMap({ PollViewCandidateModel.sampleDatasForIdentifier($0) }),
        identifiersOfVotersWhoDidNotVoteYet: VoterWhoDidNotVoteYetViewModel.VoterIdentifier.sampleDatas)
    
    @MainActor
    static func sampleDatas(candidatesSortOrder: PollViewModel.CandidatesSortOrder) -> Self {
        switch candidatesSortOrder {
        case .pollOrder:
            return Self.sampleData
        case .numberOfResponses:
            let sortedCandidates = sampleData.candidatesWithResponses.sorted { candidate1, candidate2 in
                if candidate1.numberOfResponses == candidate2.numberOfResponses {
                    return candidate1.text < candidate2.text // Just for previews
                } else {
                    return candidate1.numberOfResponses > candidate2.numberOfResponses
                }
            }
            return .init(question: Self.sampleData.question,
                         candidates: sortedCandidates,
                         identifiersOfVotersWhoDidNotVoteYet: Self.sampleData.identifiersOfVotersWhoDidNotVoteYet)
        }
    }
    
}

//extension PollViewModel {
//    
//    @MainActor
//    static var sampleData: Self = .init(
//        question: "Question 1",
//        candidates: PollCandidateIdentifier.sampleDatas.compactMap({ PollViewCandidateModel.sampleDatasForIdentifier($0) }),
//        waitingAnswers: [PollWaitingAnswerModel])
//
//}


//extension PollViewModel {
//
//    @MainActor
//    static var sampleDatas: [Self] = [
//        .init(question: "Question 1", candidates: PollViewCandidateModel.sampleDatas, avatarModel: ObvAvatarViewModel.sampleDatas[0], waitingAnswers: [PollWaitingAnswerModel(name: "Bertrand Delanöe", avatarModel: ObvAvatarViewModel.sampleDatas[1]), PollWaitingAnswerModel(name: "Chris Mas", avatarModel: ObvAvatarViewModel.sampleDatas[2]), PollWaitingAnswerModel(name: "Dimitri Maximov", avatarModel: ObvAvatarViewModel.sampleDatas[3])])
//    ]
//}
