/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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

import Testing
import ObvAppTypes
import ObvTypes
import ObvCrypto


struct ObvDiscussionIdentifierTests {
    
    private static let identitiesAsURLs: [URL] = [
        URL(string: "https://invitation.olvid.io/#AwAAAIAAAAAAXmh0dHBzOi8vc2VydmVyLmRldi5vbHZpZC5pbwAA1-NJhAuO742VYzS5WXQnM3ACnlxX_ZTYt9BUHrotU2UBA_FlTxBTrcgXN9keqcV4-LOViz3UtdEmTZppHANX3JYAAAAAGEFsaWNlIFdvcmsgKENFTyBAIE9sdmlkKQ==")!,
        URL(string: "https://invitation.olvid.io/#AwAAAHAAAAAAXmh0dHBzOi8vc2VydmVyLmRldi5vbHZpZC5pbwAAVZx8aqikpCe4h3ayCwgKBf-2nDwz-a6vxUo3-ep5azkBUjimUf3J--GXI8WTc2NIysQbw5fxmsY9TpjnDsZMW-AAAAAACEJvYiBXb3Jr")!,
    ]
    
    private static let cryptoIds = identitiesAsURLs.map({ ObvURLIdentity(urlRepresentation: $0)!.cryptoId })

    @Test func testObvDiscussionIdentifierForLosslessStringConvertibleWhenOneToOne() async throws {
        let ownedCryptoId = Self.cryptoIds[0]
        let contactCryptoId = Self.cryptoIds[1]
        let id = ObvContactIdentifier(contactCryptoId: contactCryptoId, ownedCryptoId: ownedCryptoId)
        let discussionIdentifier = ObvDiscussionIdentifier.oneToOne(id: id)
        let description = discussionIdentifier.description
        guard let recoveredDiscussionIdentifier = ObvDiscussionIdentifier(description) else {
            #expect(Bool(false))
            return
        }
        switch discussionIdentifier {
        case .oneToOne(id: let id1):
            switch recoveredDiscussionIdentifier {
            case .oneToOne(id: let id2):
                #expect(id1 == id2)
            case .groupV1:
                #expect(Bool(false))
            case .groupV2:
                #expect(Bool(false))
            }
        case .groupV1:
            #expect(Bool(false))
        case .groupV2:
            #expect(Bool(false))
        }
        #expect(discussionIdentifier == recoveredDiscussionIdentifier)
    }

    
    @Test func testObvDiscussionIdentifierForLosslessStringConvertibleWhenGroupV1() async throws {
        let ownedCryptoId = Self.cryptoIds[0]
        let groupOwner = Self.cryptoIds[1]
        let groupUid = UID.zero
        let groupV1Identifier = GroupV1Identifier(groupUid: groupUid, groupOwner: groupOwner)
        let id = ObvGroupV1Identifier(ownedCryptoId: ownedCryptoId, groupV1Identifier: groupV1Identifier)
        let discussionIdentifier = ObvDiscussionIdentifier.groupV1(id: id)
        let description = discussionIdentifier.description
        guard let recoveredDiscussionIdentifier = ObvDiscussionIdentifier(description) else {
            #expect(Bool(false))
            return
        }
        switch discussionIdentifier {
        case .oneToOne:
            #expect(Bool(false))
        case .groupV1(id: let id1):
            switch recoveredDiscussionIdentifier {
            case .oneToOne:
                #expect(Bool(false))
            case .groupV1(id: let id2):
                #expect(id1 == id2)
            case .groupV2:
                #expect(Bool(false))
            }
        case .groupV2:
            #expect(Bool(false))
        }
        #expect(discussionIdentifier == recoveredDiscussionIdentifier)
    }

    
    @Test func testObvDiscussionIdentifierForLosslessStringConvertibleWhenGroupV2() async throws {
        let ownedCryptoId = Self.cryptoIds[0]
        let groupUID = UID.zero
        let groupV2Identifier = ObvGroupV2.Identifier(groupUID: groupUID, serverURL: URL(string: "https://test.olvid.io")!, category: .server)
        let id = ObvGroupV2Identifier(ownedCryptoId: ownedCryptoId, identifier: groupV2Identifier)
        let discussionIdentifier = ObvDiscussionIdentifier.groupV2(id: id)
        guard let recoveredDiscussionIdentifier = ObvDiscussionIdentifier(discussionIdentifier.description) else {
            #expect(Bool(false))
            return
        }
        switch discussionIdentifier {
        case .oneToOne:
            #expect(Bool(false))
        case .groupV1:
            #expect(Bool(false))
        case .groupV2(let id1):
            switch recoveredDiscussionIdentifier {
            case .oneToOne:
                #expect(Bool(false))
            case .groupV1:
                #expect(Bool(false))
            case .groupV2(let id2):
                #expect(id1 == id2)
            }
        }
        #expect(discussionIdentifier == recoveredDiscussionIdentifier)
    }
    
    @Test func testSentObvMessageAppIdentifierForForLosslessStringConvertibleWhenOneToOne() async throws {
        
        let ownedCryptoId = Self.cryptoIds[0]
        let contactCryptoId = Self.cryptoIds[1]
        let id = ObvContactIdentifier(contactCryptoId: contactCryptoId, ownedCryptoId: ownedCryptoId)
        let discussionIdentifier = ObvDiscussionIdentifier.oneToOne(id: id)

        do {
            
            let senderThreadIdentifier = UUID()
            let senderSequenceNumber = 42
            let messageAppIdentifier = ObvMessageAppIdentifier.sent(discussionIdentifier: discussionIdentifier, senderThreadIdentifier: senderThreadIdentifier, senderSequenceNumber: senderSequenceNumber)
         
            guard let recoveredMessageAppIdentifier = ObvMessageAppIdentifier(messageAppIdentifier.description) else {
                #expect(Bool(false))
                return
            }

            switch messageAppIdentifier {
            case .received:
                #expect(Bool(false))
            case .sent(let discussionIdentifier1, let senderThreadIdentifier1, let senderSequenceNumber1):
                switch recoveredMessageAppIdentifier {
                case .received:
                    #expect(Bool(false))
                case .sent(let discussionIdentifier2, let senderThreadIdentifier2, let senderSequenceNumber2):
                    #expect(discussionIdentifier1 == discussionIdentifier2)
                    #expect(senderThreadIdentifier1 == senderThreadIdentifier2)
                    #expect(senderSequenceNumber1 == senderSequenceNumber2)
                }
            }
            
        }
        
    }
    
    @Test func testReceivedObvMessageAppIdentifierForObvEncodedWhenOneToOne() async throws {
        
        let ownedCryptoId = Self.cryptoIds[0]
        let contactCryptoId = Self.cryptoIds[1]
        let id = ObvContactIdentifier(contactCryptoId: contactCryptoId, ownedCryptoId: ownedCryptoId)
        let discussionIdentifier = ObvDiscussionIdentifier.oneToOne(id: id)

        do {
            
            let senderThreadIdentifier = UUID()
            let senderSequenceNumber = 42
            let senderIdentifier = contactCryptoId.getIdentity()
            let messageAppIdentifier = ObvMessageAppIdentifier.received(discussionIdentifier: discussionIdentifier, senderIdentifier: senderIdentifier, senderThreadIdentifier: senderThreadIdentifier, senderSequenceNumber: senderSequenceNumber)
         
            let obvEncoded = messageAppIdentifier.obvEncode()
            
            guard let recoveredMessageAppIdentifier = ObvMessageAppIdentifier(obvEncoded) else {
                #expect(Bool(false))
                return
            }

            switch messageAppIdentifier {
            case .sent:
                #expect(Bool(false))
            case .received(let discussionIdentifier1, let senderIdentifier1, let senderThreadIdentifier1, let senderSequenceNumber1):
                switch recoveredMessageAppIdentifier {
                case .sent:
                    #expect(Bool(false))
                case .received(let discussionIdentifier2, let senderIdentifier2, let senderThreadIdentifier2, let senderSequenceNumber2):
                    #expect(discussionIdentifier1 == discussionIdentifier2)
                    #expect(senderIdentifier1 == senderIdentifier2)
                    #expect(senderThreadIdentifier1 == senderThreadIdentifier2)
                    #expect(senderSequenceNumber1 == senderSequenceNumber2)
                }
            }
            
        }
        
    }
    

    
    @Test func testReceivedObvMessageAppIdentifierForForLosslessStringConvertibleWhenOneToOne() async throws {
        
        let ownedCryptoId = Self.cryptoIds[0]
        let contactCryptoId = Self.cryptoIds[1]
        let id = ObvContactIdentifier(contactCryptoId: contactCryptoId, ownedCryptoId: ownedCryptoId)
        let discussionIdentifier = ObvDiscussionIdentifier.oneToOne(id: id)

        do {
            
            let senderThreadIdentifier = UUID()
            let senderSequenceNumber = 42
            let senderIdentifier = contactCryptoId.getIdentity()
            let messageAppIdentifier = ObvMessageAppIdentifier.received(discussionIdentifier: discussionIdentifier, senderIdentifier: senderIdentifier, senderThreadIdentifier: senderThreadIdentifier, senderSequenceNumber: senderSequenceNumber)
         
            guard let recoveredMessageAppIdentifier = ObvMessageAppIdentifier(messageAppIdentifier.description) else {
                #expect(Bool(false))
                return
            }

            switch messageAppIdentifier {
            case .sent:
                #expect(Bool(false))
            case .received(let discussionIdentifier1, let senderIdentifier1, let senderThreadIdentifier1, let senderSequenceNumber1):
                switch recoveredMessageAppIdentifier {
                case .sent:
                    #expect(Bool(false))
                case .received(let discussionIdentifier2, let senderIdentifier2, let senderThreadIdentifier2, let senderSequenceNumber2):
                    #expect(discussionIdentifier1 == discussionIdentifier2)
                    #expect(senderIdentifier1 == senderIdentifier2)
                    #expect(senderThreadIdentifier1 == senderThreadIdentifier2)
                    #expect(senderSequenceNumber1 == senderSequenceNumber2)
                }
            }
            
        }
        
    }

    
    @Test func testSentObvMessageAppIdentifierForForLosslessStringConvertibleWhenGroupV1() async throws {
        
        let ownedCryptoId = Self.cryptoIds[0]
        let groupOwner = Self.cryptoIds[1]
        let groupUid = UID.zero
        let groupV1Identifier = GroupV1Identifier(groupUid: groupUid, groupOwner: groupOwner)
        let id = ObvGroupV1Identifier(ownedCryptoId: ownedCryptoId, groupV1Identifier: groupV1Identifier)
        let discussionIdentifier = ObvDiscussionIdentifier.groupV1(id: id)

        do {
            
            let senderThreadIdentifier = UUID()
            let senderSequenceNumber = 42
            let messageAppIdentifier = ObvMessageAppIdentifier.sent(discussionIdentifier: discussionIdentifier, senderThreadIdentifier: senderThreadIdentifier, senderSequenceNumber: senderSequenceNumber)
         
            guard let recoveredMessageAppIdentifier = ObvMessageAppIdentifier(messageAppIdentifier.description) else {
                #expect(Bool(false))
                return
            }

            switch messageAppIdentifier {
            case .received:
                #expect(Bool(false))
            case .sent(let discussionIdentifier1, let senderThreadIdentifier1, let senderSequenceNumber1):
                switch recoveredMessageAppIdentifier {
                case .received:
                    #expect(Bool(false))
                case .sent(let discussionIdentifier2, let senderThreadIdentifier2, let senderSequenceNumber2):
                    #expect(discussionIdentifier1 == discussionIdentifier2)
                    #expect(senderThreadIdentifier1 == senderThreadIdentifier2)
                    #expect(senderSequenceNumber1 == senderSequenceNumber2)
                }
            }
            
        }
        
    }

    
    @Test func testReceivedObvMessageAppIdentifierForForLosslessStringConvertibleWhenGroupV1() async throws {
        
        let ownedCryptoId = Self.cryptoIds[0]
        let groupOwner = Self.cryptoIds[1]
        let groupUid = UID.zero
        let groupV1Identifier = GroupV1Identifier(groupUid: groupUid, groupOwner: groupOwner)
        let id = ObvGroupV1Identifier(ownedCryptoId: ownedCryptoId, groupV1Identifier: groupV1Identifier)
        let discussionIdentifier = ObvDiscussionIdentifier.groupV1(id: id)

        do {
            
            let senderThreadIdentifier = UUID()
            let senderSequenceNumber = 42
            let senderIdentifier = groupOwner.getIdentity()
            let messageAppIdentifier = ObvMessageAppIdentifier.received(discussionIdentifier: discussionIdentifier, senderIdentifier: senderIdentifier, senderThreadIdentifier: senderThreadIdentifier, senderSequenceNumber: senderSequenceNumber)
         
            guard let recoveredMessageAppIdentifier = ObvMessageAppIdentifier(messageAppIdentifier.description) else {
                #expect(Bool(false))
                return
            }

            switch messageAppIdentifier {
            case .sent:
                #expect(Bool(false))
            case .received(let discussionIdentifier1, let senderIdentifier1, let senderThreadIdentifier1, let senderSequenceNumber1):
                switch recoveredMessageAppIdentifier {
                case .sent:
                    #expect(Bool(false))
                case .received(let discussionIdentifier2, let senderIdentifier2, let senderThreadIdentifier2, let senderSequenceNumber2):
                    #expect(discussionIdentifier1 == discussionIdentifier2)
                    #expect(senderIdentifier1 == senderIdentifier2)
                    #expect(senderThreadIdentifier1 == senderThreadIdentifier2)
                    #expect(senderSequenceNumber1 == senderSequenceNumber2)
                }
            }
            
        }
        
    }

    
    @Test func testSentObvMessageAppIdentifierForForLosslessStringConvertibleWhenGroupV2() async throws {
        
        let ownedCryptoId = Self.cryptoIds[0]
        let groupUID = UID.zero
        let groupV2Identifier = ObvGroupV2.Identifier(groupUID: groupUID, serverURL: URL(string: "https://test.olvid.io")!, category: .server)
        let id = ObvGroupV2Identifier(ownedCryptoId: ownedCryptoId, identifier: groupV2Identifier)
        let discussionIdentifier = ObvDiscussionIdentifier.groupV2(id: id)

        do {
            
            let senderThreadIdentifier = UUID()
            let senderSequenceNumber = 42
            let messageAppIdentifier = ObvMessageAppIdentifier.sent(discussionIdentifier: discussionIdentifier, senderThreadIdentifier: senderThreadIdentifier, senderSequenceNumber: senderSequenceNumber)
         
            guard let recoveredMessageAppIdentifier = ObvMessageAppIdentifier(messageAppIdentifier.description) else {
                #expect(Bool(false))
                return
            }

            switch messageAppIdentifier {
            case .received:
                #expect(Bool(false))
            case .sent(let discussionIdentifier1, let senderThreadIdentifier1, let senderSequenceNumber1):
                switch recoveredMessageAppIdentifier {
                case .received:
                    #expect(Bool(false))
                case .sent(let discussionIdentifier2, let senderThreadIdentifier2, let senderSequenceNumber2):
                    #expect(discussionIdentifier1 == discussionIdentifier2)
                    #expect(senderThreadIdentifier1 == senderThreadIdentifier2)
                    #expect(senderSequenceNumber1 == senderSequenceNumber2)
                }
            }
            
        }
        
    }

    
    @Test func testReceivedObvMessageAppIdentifierForForLosslessStringConvertibleWhenGroupV2() async throws {
        
        let ownedCryptoId = Self.cryptoIds[0]
        let contactCryptoId = Self.cryptoIds[1]
        let groupUID = UID.zero
        let groupV2Identifier = ObvGroupV2.Identifier(groupUID: groupUID, serverURL: URL(string: "https://test.olvid.io")!, category: .server)
        let id = ObvGroupV2Identifier(ownedCryptoId: ownedCryptoId, identifier: groupV2Identifier)
        let discussionIdentifier = ObvDiscussionIdentifier.groupV2(id: id)

        do {
            
            let senderThreadIdentifier = UUID()
            let senderSequenceNumber = 42
            let senderIdentifier = contactCryptoId.getIdentity()
            let messageAppIdentifier = ObvMessageAppIdentifier.received(discussionIdentifier: discussionIdentifier, senderIdentifier: senderIdentifier, senderThreadIdentifier: senderThreadIdentifier, senderSequenceNumber: senderSequenceNumber)
         
            guard let recoveredMessageAppIdentifier = ObvMessageAppIdentifier(messageAppIdentifier.description) else {
                #expect(Bool(false))
                return
            }

            switch messageAppIdentifier {
            case .sent:
                #expect(Bool(false))
            case .received(let discussionIdentifier1, let senderIdentifier1, let senderThreadIdentifier1, let senderSequenceNumber1):
                switch recoveredMessageAppIdentifier {
                case .sent:
                    #expect(Bool(false))
                case .received(let discussionIdentifier2, let senderIdentifier2, let senderThreadIdentifier2, let senderSequenceNumber2):
                    #expect(discussionIdentifier1 == discussionIdentifier2)
                    #expect(senderIdentifier1 == senderIdentifier2)
                    #expect(senderThreadIdentifier1 == senderThreadIdentifier2)
                    #expect(senderSequenceNumber1 == senderSequenceNumber2)
                }
            }
            
        }
        
    }

}
