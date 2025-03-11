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

public typealias ObvDictionary = [Data: ObvEncoded]


extension ObvDictionary {
    
    private static func makeError(message: String, code: Int = 0) -> Error {
        let userInfo = [NSLocalizedFailureReasonErrorKey: message]
        return NSError(domain: "ObvDictionary", code: code, userInfo: userInfo)
    }
    
    // Encoding
    
    mutating public func obvEncode<T: ObvEncodable>(_ value: T, forKey key: CodingKey) throws {
        guard let dataKey = key.stringValue.data(using: .utf8) else { throw Self.makeError(message: "Could not encode dictionnary key") }
        self.updateValue(value.obvEncode(), forKey: dataKey)
    }

    mutating public func obvEncode<T: ObvFailableEncodable>(_ value: T, forKey key: CodingKey) throws {
        guard let dataKey = key.stringValue.data(using: .utf8) else { throw Self.makeError(message: "Could not encode dictionnary key") }
        self.updateValue(try value.obvEncode(), forKey: dataKey)
    }

    mutating public func obvEncode<T: ObvEncodable>(_ value: Set<T>, forKey key: CodingKey) throws {
        guard let dataKey = key.stringValue.data(using: .utf8) else { throw Self.makeError(message: "Could not encode dictionnary key") }
        self.updateValue(value.map({ $0.obvEncode() }).obvEncode(), forKey: dataKey)
    }

    mutating public func obvEncodeIfPresent<T: ObvEncodable>(_ value: T?, forKey key: CodingKey) throws {
        guard let value = value else { return }
        try self.obvEncode(value, forKey: key)
    }

    mutating public func obvEncodeIfPresent<T: ObvEncodable>(_ value: Set<T>?, forKey key: CodingKey) throws {
        guard let value = value else { return }
        try self.obvEncode(value, forKey: key)
    }

    mutating public func obvEncodeIfPresent<T: ObvFailableEncodable>(_ value: T?, forKey key: CodingKey) throws {
        guard let value = value else { return }
        try self.obvEncode(value, forKey: key)
    }
    
    mutating public func updateValueIfPresent(_ value: ObvEncoded?, forKey key: CodingKey) throws {
        guard let value = value else { return }
        try updateValue(value, forKey: key)
    }

    mutating public func updateValue(_ value: ObvEncoded, forKey key: CodingKey) throws {
        guard let dataKey = key.stringValue.data(using: .utf8) else { throw Self.makeError(message: "Could not encode dictionnary key") }
        self.updateValue(value, forKey: dataKey)
    }

    // Decoding
    
    public func obvDecode(_ type: ObvEncoded.Type, forKey key: CodingKey) throws -> ObvEncoded {
        guard let encodedValue = try obvDecodeIfPresent(type, forKey: key) else { throw Self.makeError(message: "Could not find value for key \(key.stringValue)") }
        return encodedValue
    }

    
    public func obvDecodeIfPresent(_ type: ObvEncoded.Type, forKey key: CodingKey) throws -> ObvEncoded? {
        guard let dataKey = key.stringValue.data(using: .utf8) else { throw Self.makeError(message: "Could not encode dictionnary key") }
        return self[dataKey]
    }

        
    public func obvDecodeIfPresent<T: ObvDecodable>(_ type: T.Type, forKey key: CodingKey) throws -> T? {
        let encodedValue = try self.obvDecodeIfPresent(ObvEncoded.self, forKey: key)
        return try encodedValue?.obvDecode()
    }

    
    public func obvDecode<T: ObvDecodable>(_ type: T.Type, forKey key: CodingKey) throws -> T {
        let encodedValue = try self.obvDecode(ObvEncoded.self, forKey: key)
        return try encodedValue.obvDecode()
    }

    
    public func obvDecode<T: ObvDecodable>(_ type: Set<T>.Type, forKey key: CodingKey) throws -> Set<T> {
        let encodedValue = try self.obvDecode(ObvEncoded.self, forKey: key)
        guard let encodedElements = [ObvEncoded](encodedValue) else { throw Self.makeError(message: "Could not parse encoded set") }
        let decodedElements: [T] = try encodedElements.map({ try $0.obvDecode() })
        return Set(decodedElements)
    }

    
    public func obvDecodeIfPresent<T: ObvDecodable>(_ type: Set<T>.Type, forKey key: CodingKey) throws -> Set<T>? {
        guard let encodedValue = try self.obvDecodeIfPresent(ObvEncoded.self, forKey: key) else { return nil }
        guard let encodedElements = [ObvEncoded](encodedValue) else { throw Self.makeError(message: "Could not parse encoded set") }
        let decodedElements: [T] = try encodedElements.map({ try $0.obvDecode() })
        return Set(decodedElements)
    }

    
    public func obvDecode<T: ObvDecodable>(_ type: Array<T>.Type, forKey key: CodingKey) throws -> Set<T> {
        let encodedValue = try self.obvDecode(ObvEncoded.self, forKey: key)
        guard let encodedElements = [ObvEncoded](encodedValue) else { throw Self.makeError(message: "Could not parse encoded array") }
        let decodedElements: [T] = try encodedElements.map({ try $0.obvDecode() })
        return Set(decodedElements)
    }

    public func getValue(forKey key: CodingKey) throws -> ObvEncoded {
        guard let value = try getValueIfPresent(forKey: key) else { throw Self.makeError(message: "Key does not exist") }
        return value
    }

    public func getValueIfPresent(forKey key: CodingKey) throws -> ObvEncoded? {
        guard let dataKey = key.stringValue.data(using: .utf8) else { throw Self.makeError(message: "Could not encode dictionnary key") }
        return self[dataKey]
    }

}
