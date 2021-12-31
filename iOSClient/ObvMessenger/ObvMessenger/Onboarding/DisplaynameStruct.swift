/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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

// Should only be used under iOS12 or less
struct DisplaynameStruct: Equatable {
    
    let firstName: String?
    let lastName: String?
    let company: String?
    let position: String?
    let photoURL: URL?
        
    init(firstName: String?, lastName: String?, company: String?, position: String?, photoURL: URL?) {
        if #available(iOS 13.0, *) { assertionFailure() }
        self.firstName = firstName
        self.lastName = lastName
        self.company = company
        self.position = position
        self.photoURL = photoURL
    }

    init() {
        if #available(iOS 13.0, *) { assertionFailure() }
        self.firstName = nil
        self.lastName = nil
        self.company = nil
        self.position = nil
        self.photoURL = nil
    }
    
    var isValid: Bool {
        return self.identityDetails != nil
    }
    
    var identityDetails: ObvIdentityCoreDetails? {
        return try? ObvIdentityCoreDetails(firstName: self.firstName, lastName: self.lastName, company: self.company, position: self.position, signedUserDetails: nil)
    }

    @available(iOS 13.0, *)
    var singleIdentity: SingleIdentity {
        return SingleIdentity(
            firstName: firstName,
            lastName: lastName,
            position: position,
            company: company,
            isKeycloakManaged: false,
            showGreenShield: false,
            showRedShield: false,
            identityColors: nil,
            photoURL: nil)
    }

    func settingFirstName(firstName: String?) throws -> DisplaynameStruct {
        return DisplaynameStruct(firstName: firstName, lastName: lastName, company: company, position: position, photoURL: photoURL)
    }

    func settingLastName(lastName: String?) throws -> DisplaynameStruct {
        return DisplaynameStruct(firstName: firstName, lastName: lastName, company: company, position: position, photoURL: photoURL)
    }

    func settingCompany(company: String?) throws -> DisplaynameStruct {
        return DisplaynameStruct(firstName: firstName, lastName: lastName, company: company, position: position, photoURL: photoURL)
    }

    func settingPosition(position: String?) throws -> DisplaynameStruct {
        return DisplaynameStruct(firstName: firstName, lastName: lastName, company: company, position: position, photoURL: photoURL)
    }
    
    static let errorDomain = "DisplaynameStruct"
    private static func makeError(message: String) -> Error { NSError(domain: DisplaynameStruct.errorDomain, code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    private func makeError(message: String) -> Error { DisplaynameStruct.makeError(message: message) }

}
