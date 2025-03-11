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

import XCTest
import ObvCrypto
@testable import ObvTypes

final class ObvTypesTests: XCTestCase {
    
    private static let identitiesAsURLs: [URL] = [
        URL(string: "https://invitation.olvid.io/#AwAAAIAAAAAAXmh0dHBzOi8vc2VydmVyLmRldi5vbHZpZC5pbwAA1-NJhAuO742VYzS5WXQnM3ACnlxX_ZTYt9BUHrotU2UBA_FlTxBTrcgXN9keqcV4-LOViz3UtdEmTZppHANX3JYAAAAAGEFsaWNlIFdvcmsgKENFTyBAIE9sdmlkKQ==")!,
        URL(string: "https://invitation.olvid.io/#AwAAAHAAAAAAXmh0dHBzOi8vc2VydmVyLmRldi5vbHZpZC5pbwAAVZx8aqikpCe4h3ayCwgKBf-2nDwz-a6vxUo3-ep5azkBUjimUf3J--GXI8WTc2NIysQbw5fxmsY9TpjnDsZMW-AAAAAACEJvYiBXb3Jr")!,
    ]
    
    private static let cryptoIds = identitiesAsURLs.map({ ObvURLIdentity(urlRepresentation: $0)!.cryptoId })

    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testUID() {
        let uid1 = UID.init(uid: Data(repeating: 0x12, count: 32))
        let uid2 = UID.init(uid: Data(repeating: 0x12, count: 32))
        XCTAssertEqual(uid1!.hashValue, uid2!.hashValue)
    }
    
    
    func testObvContactIdentifierForObvCodable() {
        
        let obvContactIdentifier = ObvContactIdentifier(contactCryptoId: Self.cryptoIds[0], ownedCryptoId: Self.cryptoIds[1])
        let encoded = obvContactIdentifier.obvEncode()
        let recovered = ObvContactIdentifier(encoded)
        XCTAssertEqual(obvContactIdentifier, recovered)
        
    }
    
    
    func testObvContactIdentifierForLosslessStringConvertible() {
        
        let obvContactIdentifier = ObvContactIdentifier(contactCryptoId: Self.cryptoIds[0], ownedCryptoId: Self.cryptoIds[1])
        let description = obvContactIdentifier.description
        let recovered = ObvContactIdentifier(description)
        XCTAssertEqual(obvContactIdentifier, recovered)
        
    }
    
    
    func testObvKeycloakConfigurationCoding() {
        
        do {
            let keycloakServerURL = URL(string: "https://olvid.io/test")!
            let clientId = "clientId"
            let clientSecret = "clientSecret"
            
            let keycloakConfiguration = ObvKeycloakConfiguration(
                keycloakServerURL: keycloakServerURL,
                clientId: clientId,
                clientSecret: clientSecret)
            
            let encoded = try keycloakConfiguration.jsonEncode()
            
            let decodeKeycloakConfiguration = try ObvKeycloakConfiguration.jsonDecode(encoded)
            
            XCTAssert(keycloakConfiguration == decodeKeycloakConfiguration)
            XCTAssert(decodeKeycloakConfiguration.keycloakServerURL == keycloakServerURL)
            XCTAssert(decodeKeycloakConfiguration.clientId == clientId)
            XCTAssert(decodeKeycloakConfiguration.clientSecret == clientSecret)
            
        } catch {
            XCTFail()
        }
        
    }
    
}
