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
import ObvTypes


// MARK: - Group type and associated permissions

public enum ObvGroupType: Codable, Equatable, Hashable, Sendable {
    
    case standard
    case managed
    case readOnly
    case advanced(isReadOnly: Bool, remoteDeleteAnythingPolicy: RemoteDeleteAnythingPolicy)

    
    public enum RemoteDeleteAnythingPolicy: String, Codable, Equatable, CaseIterable, Comparable, Identifiable, Sendable {
        
        case nobody = "nobody"
        case admins = "admins"
        case everyone = "everyone"
        
        public var id: Self { self }
        
        private var sortOrder: Int {
            switch self {
            case .nobody: return 0
            case .admins: return 1
            case .everyone: return 2
            }
        }
        
        public static func < (lhs: RemoteDeleteAnythingPolicy, rhs: RemoteDeleteAnythingPolicy) -> Bool {
            lhs.sortOrder < rhs.sortOrder
        }

    }
    
    
    private var deserializedGroupType: DeserializedGroupType {
        switch self {
        case .standard:
            return .init(type: .standard, isReadOnly: nil, remoteDeleteAnythingPolicy: nil)
        case .managed:
            return .init(type: .managed, isReadOnly: nil, remoteDeleteAnythingPolicy: nil)
        case .readOnly:
            return .init(type: .readOnly, isReadOnly: nil, remoteDeleteAnythingPolicy: nil)
        case .advanced(isReadOnly: let isReadOnly, remoteDeleteAnythingPolicy: let remoteDeleteAnythingPolicy):
            return .init(type: .advanced, isReadOnly: isReadOnly, remoteDeleteAnythingPolicy: remoteDeleteAnythingPolicy)
        }
    }
    
    
    public func encode(to encoder: Encoder) throws {
        try self.deserializedGroupType.encode(to: encoder)
    }

    
    public init(from decoder: Decoder) throws {
        let deserializedGroupType = try DeserializedGroupType(from: decoder)
        switch deserializedGroupType.type {
        case .standard:
            self = .standard
        case .managed:
            self = .managed
        case .readOnly:
            self = .readOnly
        case .advanced:
            assert(deserializedGroupType.isReadOnly != nil)
            assert(deserializedGroupType.remoteDeleteAnythingPolicy != nil)
            self = .advanced(isReadOnly: deserializedGroupType.isReadOnly ?? false, remoteDeleteAnythingPolicy: deserializedGroupType.remoteDeleteAnythingPolicy ?? .nobody)
        }
    }

    
    public func toSerializedGroupType() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self.deserializedGroupType)
    }
    
    
    public init(serializedGroupType: Data) throws {
        let decoder = JSONDecoder()
        self = try decoder.decode(ObvGroupType.self, from: serializedGroupType)
    }

    
    /// Helper struct, allowing to serialize/deserialize a ``GroupType``.
    private struct DeserializedGroupType: Codable {
        
        let type: GroupTypeValue
        let isReadOnly: Bool? // Only makes sense if type is custom
        let remoteDeleteAnythingPolicy: RemoteDeleteAnythingPolicy? // Only makes sense if type is custom

        enum GroupTypeValue: String, Codable {
            case standard = "simple"
            case managed = "private"
            case readOnly = "read_only"
            case advanced = "custom"
        }

        private enum CodingKeys: String, CodingKey {
            case type = "type"
            case isReadOnly = "ro"
            case remoteDeleteAnythingPolicy = "del"
        }
        
    }
    
}


extension ObvGroupType {
    
    public static func adminCanSelectSpecificAdmins(groupType: ObvGroupType) -> Bool {
        switch groupType {
        case .standard:
            return false // In a standard group, every member is an administrator
        case .managed:
            return true
        case .readOnly:
            return true
        case .advanced:
            return true
        }
    }
    
}



extension ObvGroupType {
    
    public enum AdminOrRegularMember {
        case admin
        case regularMember
    }

    /// Returns the **exact** set of permissions of an admin or a regular member, for a given group type.
    public static func exactPermissions(of adminOrRegularMember: AdminOrRegularMember, forGroupType groupType: ObvGroupType) -> Set<ObvGroupV2.Permission> {

        let permissions: [ObvGroupV2.Permission]
        let isAdmin = adminOrRegularMember == .admin

        switch groupType {

        case .standard:
            permissions = ObvGroupV2.Permission.allCases.filter { permission in
                switch permission {
                case .groupAdmin: return true
                case .remoteDeleteAnything: return false
                case .editOrRemoteDeleteOwnMessages: return true
                case .changeSettings: return true
                case .sendMessage: return true
                }
            }

        case .managed:
            permissions = ObvGroupV2.Permission.allCases.filter { permission in
                switch permission {
                case .groupAdmin: return isAdmin
                case .remoteDeleteAnything: return false
                case .editOrRemoteDeleteOwnMessages: return true
                case .changeSettings: return isAdmin
                case .sendMessage: return true
                }
            }

        case .readOnly:
            permissions = ObvGroupV2.Permission.allCases.filter { permission in
                switch permission {
                case .groupAdmin: return isAdmin
                case .remoteDeleteAnything: return false
                case .editOrRemoteDeleteOwnMessages: return true
                case .changeSettings: return isAdmin
                case .sendMessage: return isAdmin
                }
            }

        case .advanced(isReadOnly: let isReadOnly, remoteDeleteAnythingPolicy: let remoteDeleteAnythingPolicy):
            permissions = ObvGroupV2.Permission.allCases.filter { permission in
                switch permission {
                case .groupAdmin: return isAdmin
                case .remoteDeleteAnything:
                    switch remoteDeleteAnythingPolicy {
                    case .nobody:
                        return false
                    case .admins:
                        return isAdmin
                    case .everyone:
                        return true
                    }
                case .editOrRemoteDeleteOwnMessages: return true
                case .changeSettings: return isAdmin
                case .sendMessage: return isReadOnly ? isAdmin : true
                }
            }
        }
        
        return Set(permissions)
        
    }

    
}
