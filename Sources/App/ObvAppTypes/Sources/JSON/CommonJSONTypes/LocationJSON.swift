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


public struct LocationJSON: Codable, Equatable, Hashable, Sendable {

    public enum LocationSharingType: Int, Sendable {
        case SEND = 1
        case SHARING = 2
        case END_SHARING = 3
    }
    
    public enum LocationQuality: Int {
        case QUALITY_PRECISE = 1
        case QUALITY_BALANCED = 2
        case QUALITY_POWER_SAVE = 3
    }
    public let type: LocationJSON.LocationSharingType
    public let timeIntervalSince1970: TimeInterval? // location timestamp
    public let count: Int? // null if not sharing
    public let quality: Int? // one of QUALITY_PRECISE, QUALITY_BALANCED, or QUALITY_POWER_SAVE for sharing. Null for TYPE_SEND. Not used in the Swift version of the app.
    public let sharingExpiration: TimeInterval? // can be null if endless sharing (else in ms)
    public let latitude: Double
    public let longitude: Double
    
    public let altitude: Double? // meters (default value null)
    public let precision: Double? // meters (default value null)
    public let address: String? // (default value empty string or null)
    
    public var locationData: ObvLocationData {
        ObvLocationData(timestamp: timestamp,
                        latitude: latitude,
                        longitude: longitude,
                        altitude: altitude,
                        precision: precision,
                        address: address,
                        isStationary: false)
    }
    
    var timestamp: Date? {
        guard let timeIntervalSince1970 else { return nil }
        return Date(timeIntervalSince1970: timeIntervalSince1970)
    }
    
    public var expirationDate: ObvLocationSharingExpirationDate {
        if let sharingExpiration {
            return .after(date: Date(timeIntervalSince1970: sharingExpiration))
        } else {
            return .never
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case count = "c"
        case sharingExpiration = "se"
        case quality = "q"
        case type = "t"
        case timeIntervalSince1970 = "ts"
        case longitude = "long"
        case latitude = "lat"
        case altitude = "alt"
        case precision = "prec"
        case address = "add"
    }

    enum ExpirationJSONCodingError: Error {
        case decoding(String)
    }
    
    public init(type: LocationJSON.LocationSharingType,
                timestamp: Date?,
                count: Int?,
                quality: Int?,
                sharingExpiration: TimeInterval?,
                latitude: Double,
                longitude: Double,
                altitude: Double?,
                precision: Double?,
                address: String?) {
        self.type = type
        self.timeIntervalSince1970 = timestamp?.timeIntervalSince1970
        self.count = count
        self.quality = quality
        self.sharingExpiration = sharingExpiration
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.precision = precision
        self.address = address
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        let typeRawValue = try container.decode(Int.self, forKey: .type)
        self.type = LocationJSON.LocationSharingType(rawValue: typeRawValue) ?? .SEND
        
        self.longitude = try container.decode(Double.self, forKey: .longitude)
        self.latitude = try container.decode(Double.self, forKey: .latitude)
        
        if let timeIntervalSince1970InMilliseconds = try container.decodeIfPresent(Int.self, forKey: .timeIntervalSince1970) {
            self.timeIntervalSince1970 = TimeInterval(milliseconds: timeIntervalSince1970InMilliseconds)
        } else {
            self.timeIntervalSince1970 = nil
        }
        
        if let count = try container.decodeIfPresent(Int.self, forKey: .count) {
            self.count = count
        } else {
            self.count = nil
        }
        
        if let quality = try container.decodeIfPresent(Int.self, forKey: .quality) {
            self.quality = quality
        } else {
            self.quality = nil
        }
        
        if let sharingExpiration = try container.decodeIfPresent(Int.self, forKey: .sharingExpiration) {
            self.sharingExpiration = TimeInterval(milliseconds: sharingExpiration)
        } else {
            self.sharingExpiration = nil
        }
        
        if let altitude = try container.decodeIfPresent(Double.self, forKey: .altitude) {
            self.altitude = altitude
        } else {
            self.altitude = nil
        }
        
        if let precision = try container.decodeIfPresent(Double.self, forKey: .precision) {
            self.precision = precision
        } else {
            self.precision = nil
        }
        
        if let address = try container.decodeIfPresent(String.self, forKey: .address) {
            self.address = address
        } else {
            self.address = nil
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.type.rawValue, forKey: .type)
        if let timestamp = timeIntervalSince1970?.toMilliseconds {
            try container.encodeIfPresent(timestamp, forKey: .timeIntervalSince1970)
        }
        try container.encode(self.longitude, forKey: .longitude)
        try container.encode(self.latitude, forKey: .latitude)

        try container.encodeIfPresent(self.count, forKey: .count)
        try container.encodeIfPresent(self.quality, forKey: .quality)
        if let sharingExpiration = sharingExpiration?.toMilliseconds {
            try container.encodeIfPresent(sharingExpiration, forKey: .sharingExpiration)
        }
        try container.encodeIfPresent(self.altitude, forKey: .altitude)
        try container.encodeIfPresent(self.precision, forKey: .precision)
        try container.encodeIfPresent(self.address, forKey: .address)
    }

    public func jsonEncode() throws -> Data {
        let encoder = JSONEncoder()
        let data = try encoder.encode(self)
        return data
    }

    static func jsonDecode(_ data: Data) throws -> LocationJSON {
        let decoder = JSONDecoder()
        return try decoder.decode(LocationJSON.self, from: data)
    }

    public static func defaultLocation(with type: LocationSharingType) -> LocationJSON {
        return LocationJSON(type: type,
                            timestamp: Date.now,
                            count: nil,
                            quality: nil,
                            sharingExpiration: nil,
                            latitude: 0,
                            longitude: 0,
                            altitude: nil,
                            precision: nil,
                            address: nil)
    }
}
