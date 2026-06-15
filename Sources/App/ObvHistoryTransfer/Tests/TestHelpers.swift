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
import ObvAppTypes


extension ObvCryptoId {
    
    static let sampleDatas: [Self] = [
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f0000b82ae0c57e570389cb03d5ad93dab4606bda7bbe01c09ce5e423094a8603a61e01693046e10e04606ef4461d31e1aa1819222a0a606a250e91749095a4410778c1")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f000009e171a9c73a0d6e9480b022154c83b13dfa8e4c99496c061c0c35b9b0432b3a014a5393f98a1aead77b813df0afee6b8af7e5f9a5aae6cb55fdb6bc5cc766f8da")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f00002d459c378a0bbc54c8be3e87e82d02347c046c4a50a6db25fe15751d8148671401054f3b14bbd7319a1f6d71746d6345332b92e193a9ea00880dd67b2f10352831")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f000089aebda5ddb3a59942d4fe6e00720b851af1c2d70b6e24e41ac8da94793a6eb70136a23bf11bcd1ccc244ab3477545cc5fee6c60c2b89b8ff2fb339f7ed2ff1f0a")!),
    ]

    static let sampleOwnedCryptoId: Self = Self.sampleDatas[0]
    static let sampleContactCryptoIds: [Self] = [
        Self.sampleDatas[1],
        Self.sampleDatas[2],
        Self.sampleDatas[3],
    ]
    
}


extension ObvContactIdentifier {

    static let sampleDatas: [Self] = [
        .init(contactCryptoId: .sampleContactCryptoIds[0], ownedCryptoId: .sampleOwnedCryptoId),
        .init(contactCryptoId: .sampleContactCryptoIds[1], ownedCryptoId: .sampleOwnedCryptoId),
        .init(contactCryptoId: .sampleContactCryptoIds[2], ownedCryptoId: .sampleOwnedCryptoId),
    ]
    
}


extension ObvDiscussionIdentifier {
    
    static let sampleData: [Self] = [
        .oneToOne(id: .sampleDatas[0]),
        .oneToOne(id: .sampleDatas[1]),
        .oneToOne(id: .sampleDatas[2]),
    ]
    
}


extension UUID {
    
    static let sampleDatas: [UUID] = (0..<ObvCryptoId.sampleDatas.count).map({ _ in UUID() })
    
    static func sampleSenderThreadIdentifier(for cryptoId: ObvCryptoId) -> Self {
        let index = ObvCryptoId.sampleDatas.firstIndex(of: cryptoId) ?? 0
        return Self.sampleDatas[index]
    }
    
}


extension ObvMessageAppIdentifier {
    
    static let sampleData: [Self] = [
        .sent(discussionIdentifier: .sampleData[0],
              senderThreadIdentifier: .sampleSenderThreadIdentifier(for: ObvCryptoId.sampleOwnedCryptoId),
              senderSequenceNumber: 0),
        .sent(discussionIdentifier: .sampleData[0],
              senderThreadIdentifier: .sampleSenderThreadIdentifier(for: ObvCryptoId.sampleOwnedCryptoId),
              senderSequenceNumber: 1),
        .received(discussionIdentifier: .sampleData[0],
                  senderIdentifier: ObvCryptoId.sampleContactCryptoIds[0].getIdentity(),
                  senderThreadIdentifier: .sampleSenderThreadIdentifier(for: ObvCryptoId.sampleContactCryptoIds[0]),
                  senderSequenceNumber: 0),
        .received(discussionIdentifier: .sampleData[0],
                  senderIdentifier: ObvCryptoId.sampleContactCryptoIds[0].getIdentity(),
                  senderThreadIdentifier: .sampleSenderThreadIdentifier(for: ObvCryptoId.sampleContactCryptoIds[0]),
                  senderSequenceNumber: 1),
        .received(discussionIdentifier: .sampleData[0],
                  senderIdentifier: ObvCryptoId.sampleContactCryptoIds[0].getIdentity(),
                  senderThreadIdentifier: .sampleSenderThreadIdentifier(for: ObvCryptoId.sampleContactCryptoIds[0]),
                  senderSequenceNumber: 2),
        .received(discussionIdentifier: .sampleData[0],
                  senderIdentifier: ObvCryptoId.sampleContactCryptoIds[0].getIdentity(),
                  senderThreadIdentifier: .sampleSenderThreadIdentifier(for: ObvCryptoId.sampleContactCryptoIds[0]),
                  senderSequenceNumber: 3),
        .received(discussionIdentifier: .sampleData[0],
                  senderIdentifier: ObvCryptoId.sampleContactCryptoIds[0].getIdentity(),
                  senderThreadIdentifier: .sampleSenderThreadIdentifier(for: ObvCryptoId.sampleContactCryptoIds[0]),
                  senderSequenceNumber: 5),
        .sent(discussionIdentifier: .sampleData[0],
              senderThreadIdentifier: .sampleSenderThreadIdentifier(for: ObvCryptoId.sampleOwnedCryptoId),
              senderSequenceNumber: 1),
    ]
    
}
