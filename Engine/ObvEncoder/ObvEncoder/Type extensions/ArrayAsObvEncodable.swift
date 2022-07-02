/*
 *  Olvid for iOS
 *  Copyright © 2019-2022 Olvid SAS
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


public extension Array where Element == ObvEncoded {
    
    private static func makeError(message: String) -> Error { NSError(domain: "Array<ObvEncoded>", code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }

    init?(_ obvEncoded: ObvEncoded) {
        guard obvEncoded.byteId == .list else { return nil }
        if let unpackedElements = ObvEncoded.unpack(obvEncoded) {
            self = unpackedElements
        } else {
            return nil
        }
    }
    
    init?(_ obvEncoded: ObvEncoded, expectedCount: Int) {
        guard let listOfEncoded = [ObvEncoded](obvEncoded) else { return nil }
        guard listOfEncoded.count == expectedCount else { return nil }
        self = listOfEncoded
    }
    
    func obvEncode() -> ObvEncoded {
        return ObvEncoded.pack(self, usingByteId: .list)
    }
    
    func obvDecode<T0: ObvDecodable>() throws -> T0 {
        guard self.count == 1 else {
            throw Self.makeError(message: "Array decode failed (unexpected count)")
        }
        return try self[0].obvDecode()
    }

    func obvDecode<T0: ObvDecodable, T1: ObvDecodable>() throws -> (T0, T1) {
        guard self.count == 2 else {
            throw Self.makeError(message: "Array decode failed (unexpected count)")
        }
        return try (self[0].obvDecode(), self[1].obvDecode())
    }

    func obvDecode<T0: ObvDecodable, T1: ObvDecodable, T2: ObvDecodable>() throws -> (T0, T1, T2) {
        guard self.count == 3 else {
            throw Self.makeError(message: "Array decode failed (unexpected count)")
        }
        return try (self[0].obvDecode(), self[1].obvDecode(), self[2].obvDecode())
    }

    func obvDecode<T0: ObvDecodable, T1: ObvDecodable, T2: ObvDecodable, T3: ObvDecodable>() throws -> (T0, T1, T2, T3) {
        guard self.count == 4 else {
            throw Self.makeError(message: "Array decode failed (unexpected count)")
        }
        return try (self[0].obvDecode(), self[1].obvDecode(), self[2].obvDecode(), self[3].obvDecode())
    }

    func obvDecode<T0: ObvDecodable, T1: ObvDecodable, T2: ObvDecodable, T3: ObvDecodable, T4: ObvDecodable>() throws -> (T0, T1, T2, T3, T4) {
        guard self.count == 5 else {
            throw Self.makeError(message: "Array decode failed (unexpected count)")
        }
        return try (self[0].obvDecode(), self[1].obvDecode(), self[2].obvDecode(), self[3].obvDecode(), self[4].obvDecode())
    }

    func obvDecode<T0: ObvDecodable, T1: ObvDecodable, T2: ObvDecodable, T3: ObvDecodable, T4: ObvDecodable, T5: ObvDecodable>() throws -> (T0, T1, T2, T3, T4, T5) {
        guard self.count == 6 else {
            throw Self.makeError(message: "Array decode failed (unexpected count)")
        }
        return try (self[0].obvDecode(), self[1].obvDecode(), self[2].obvDecode(), self[3].obvDecode(), self[4].obvDecode(), self[5].obvDecode())
    }

    func obvDecode<T0: ObvDecodable, T1: ObvDecodable, T2: ObvDecodable, T3: ObvDecodable, T4: ObvDecodable, T5: ObvDecodable, T6: ObvDecodable>() throws -> (T0, T1, T2, T3, T4, T5, T6) {
        guard self.count == 7 else {
            throw Self.makeError(message: "Array decode failed (unexpected count)")
        }
        return try (self[0].obvDecode(), self[1].obvDecode(), self[2].obvDecode(), self[3].obvDecode(), self[4].obvDecode(), self[5].obvDecode(), self[6].obvDecode())
    }

}


// The following extension leverages the previous one so as to make [ObvEncodable] conform to ObvEncodable.
extension Array: ObvEncodable where Element == ObvEncodable {
    
    public func obvEncode() -> ObvEncoded {
        let arrayOfObvEncoded = self.map { $0.obvEncode() }
        return arrayOfObvEncoded.obvEncode()
    }
    
}
