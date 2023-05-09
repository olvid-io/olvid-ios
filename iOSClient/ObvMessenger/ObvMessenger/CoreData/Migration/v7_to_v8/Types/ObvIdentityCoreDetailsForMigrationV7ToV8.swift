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
import OlvidUtils

struct ObvIdentityCoreDetailsForMigrationV7ToV8: Equatable, ObvErrorMaker {
    
    static let errorDomain = "ObvIdentityCoreDetailsForMigrationV7ToV8"
    
    let firstName: String?
    let lastName: String?
    let company: String?
    let position: String?
    
    init(firstName: String?, lastName: String?, company: String?, position: String?) throws {
        guard ObvIdentityCoreDetailsForMigrationV7ToV8.areAcceptable(firstName: firstName, lastName: lastName) else { throw Self.makeError(message: "Inacceptable core details") }
        self.firstName = firstName?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).mapToNilIfZeroLength()
        self.lastName = lastName?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).mapToNilIfZeroLength()
        self.company = company?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).mapToNilIfZeroLength()
        self.position = position?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).mapToNilIfZeroLength()
    }
    
    
    func getDisplayNameWithStyle(_ style: ObvDisplayNameStyleForMigrationV7ToV8) -> String {
        
        switch style {
            
        case .firstNameThenLastName:
            let _firstName = firstName ?? ""
            let _lastName = lastName ?? ""
            return [_firstName, _lastName].joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            
        case .positionAtCompany:
            switch (position, company) {
            case (nil, nil):
                return ""
            case (.some, nil):
                return position!
            case (nil, .some):
                return company!
            case (.some, .some):
                return [position!, company!].joined(separator: " @ ")
            }
            
        case .full:
            let firstNameThenLastName = getDisplayNameWithStyle(.firstNameThenLastName)
            if let positionAtCompany = getDisplayNameWithStyle(.positionAtCompany).mapToNilIfZeroLength() {
                return [firstNameThenLastName, "(\(positionAtCompany))"].joined(separator: " ")
            } else {
                return firstNameThenLastName
            }
            
        }
    }
    
    
    private static func areAcceptable(firstName: String?, lastName: String?) -> Bool {
        let _firstName = firstName?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).mapToNilIfZeroLength()
        let _lastName = lastName?.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).mapToNilIfZeroLength()
        return (_firstName, _lastName) != (nil, nil)
    }
    
}


extension ObvIdentityCoreDetailsForMigrationV7ToV8: Codable {
    
    enum CodingKeys: String, CodingKey {
        case firstName = "first_name"
        case lastName = "last_name"
        case company = "company"
        case position = "position"
    }
    
    
    init(_ data: Data) throws {
        let decoder = JSONDecoder()
        self = try decoder.decode(ObvIdentityCoreDetailsForMigrationV7ToV8.self, from: data)
    }
    
    
    func encode(to encoder: Encoder) throws {
        guard firstName != nil || lastName != nil else {
            let message = "Both firstName and lastName are nil, which is not allowed."
            let userInfo = [NSLocalizedFailureReasonErrorKey: message]
            throw NSError(domain: ObvIdentityCoreDetailsForMigrationV7ToV8.errorDomain, code: 0, userInfo: userInfo)
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(firstName, forKey: .firstName)
        try container.encodeIfPresent(lastName, forKey: .lastName)
        try container.encodeIfPresent(company, forKey: .company)
        try container.encodeIfPresent(position, forKey: .position)
    }
    
    
    func jsonEncode() throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(self)
    }
    
    
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let firstName = (try values.decodeIfPresent(String.self, forKey: .firstName))
        let lastName = try values.decodeIfPresent(String.self, forKey: .lastName)
        let company = try values.decodeIfPresent(String.self, forKey: .company)
        let position = try values.decodeIfPresent(String.self, forKey: .position)
        try self.init(firstName: firstName, lastName: lastName, company: company, position: position)
    }
    
    
    static func jsonDecode(_ data: Data) throws -> ObvIdentityCoreDetailsForMigrationV7ToV8 {
        let decoder = JSONDecoder()
        return try decoder.decode(ObvIdentityCoreDetailsForMigrationV7ToV8.self, from: data)
    }
    
}

// MARK: - Initializer used during migration

extension ObvIdentityCoreDetailsForMigrationV7ToV8 {
    
    init(displayName: String) {
        
        do {
            let splittedDisplayName = displayName.split(separator: "(", maxSplits: 1, omittingEmptySubsequences: true)
            switch splittedDisplayName.count {
            case 0:
                try self.init(firstName: "First Name", lastName: "Last Name", company: nil, position: nil)
            case 1:
                let (first, last) = ObvIdentityCoreDetailsForMigrationV7ToV8.firstNameAndLastNameFromString(String(splittedDisplayName[0]))
                try self.init(firstName: first, lastName: last, company: nil, position: nil)
            case 2:
                let (first, last) = ObvIdentityCoreDetailsForMigrationV7ToV8.firstNameAndLastNameFromString(String(splittedDisplayName[0]))
                var company = String(splittedDisplayName[1])
                if company.last == Character(")") {
                    _ = company.removeLast()
                }
                try self.init(firstName: first, lastName: last, company: company, position: nil)
            default:
                // Cannot happen
                let (first, last) = ObvIdentityCoreDetailsForMigrationV7ToV8.firstNameAndLastNameFromString(String(splittedDisplayName[0]))
                try self.init(firstName: first, lastName: last, company: nil, position: nil)
            }
            
        } catch {
            if displayName.isEmpty {
                try! self.init(firstName: "First Name", lastName: "Last Name", company: nil, position: nil)
            } else {
                try! self.init(firstName: displayName, lastName: nil, company: nil, position: nil)
            }
        }
        
    }
    
    private static func firstNameAndLastNameFromString(_ s: String) -> (firstName: String, lastName: String?) {
        let splittedString = s.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        switch splittedString.count {
        case 0:
            return ("First Name", "Last Name")
        case 1:
            return (String(splittedString[0]), nil)
        case 2:
            return (String(splittedString[0]), String(splittedString[1]))
        default:
            // Cannot happen thanks to maxSplits
            return (String(splittedString[0]), String(splittedString[1]))
        }
    }
    
}
