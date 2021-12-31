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

extension DisplayNameChooserViewController {
    
    struct Strings {
        
        static let sectionTitleNameEditor = NSLocalizedString("Enter your personal details", comment: "Section title")
        static let sectionTitleSeverSettings = NSLocalizedString("Server settings", comment: "Section title")

        static let urlString = NSLocalizedString("URL", comment: "")
        static let apiKey = NSLocalizedString("API Key", comment: "")

        static let firstNameLabel = NSLocalizedString("First", comment: "Must be short, label for first name")
        static let lastNameLabel = NSLocalizedString("Last", comment: "Must be short, label for last name")
        static let companyLabel = NSLocalizedString("Company", comment: "Must be short, label for the company name")
        static let positionLabel = NSLocalizedString("Position", comment: "Must be short, label for the position name within the company")
        static let mandatory = NSLocalizedString("mandatory", comment: "Indicates a mandatory text field")
        static let optional = NSLocalizedString("optional", comment: "Indicates an optional text field")
        static let titleMyId = CommonString.Title.myId
        
        static let disclaimer = NSLocalizedString("Please enter a name which will be displayed to your contacts. These details will never be sent to Olvid's servers.", comment: "Disclaimer showed during the onboarding")
        
    }
    
}
