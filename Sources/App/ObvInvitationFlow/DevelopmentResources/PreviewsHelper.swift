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
import ObvCrypto
import ObvTypes
import ObvAppTypes
import ObvDesignSystem
import ObvCells


extension UID {
    
    // 20 samples
    @MainActor
    static var sampleDatas: [UID] = (0..<20).map { itemNumber in
        return  UID(uid: Data(repeating: UInt8(itemNumber), count: 32))!
    }
    
}

extension ObvCryptoId {
    
    @MainActor
    static let sampleOwnedCryptoId: Self = try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f0000b82ae0c57e570389cb03d5ad93dab4606bda7bbe01c09ce5e423094a8603a61e01693046e10e04606ef4461d31e1aa1819222a0a606a250e91749095a4410778c1")!)
    
    // 20 samples
    @MainActor
    static let sampleDatasForContactCryptoId: [Self] = [
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000153c2183e6feef914ef20ae0f2ce4dd025022221b0bfdf22fb16859feac477fa0023713e65219d2c01f6feb26f9d2a390fd9afce7389f7ae22884f0efccad74c83")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000a7cc11bc3d5b0aaff7689da45478d11e3ac216a84fda1eee483e69d5f38239ca0087679c83bab21cd7ac8ffa73f1494b574364a8e51a99c040f7900b71d3878ac6")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f00001c94bfc08515742d03156b104173bb911e761fa388ed008773e3854f1bf3bb31003f0b55bc89f59d3c9e7eb2a74437a0fe90696318888676869fda77ed0dcdcc55")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000aeaf4fb1ed5cdbdb4ed6c8614fc4706dee09e68425d0086ce4b4ce47d8f4b9f70013013f1ea4b9ce185a35d2d6951299eba3a3a3a8a830f4c2635c74fcec04ac14")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000b9d6817d5e4461249b5901c8fbb85d0dd68c0ff42b03920ff04ff8f00eb8f6f4000cf3ca06cc84cc1759a9d116b89beba5899fc338a29ecff0dd0bb09afe575a7b")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000bed9ed0323efe2d2b3bfa4f1f74a3e5cacd65e0dc30190e241076f247059282a00a36cc9ae36bb78bef9543169e174cf4bca438ad62866aaaf61554882348afc5f")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f00004356b99304f36dc3357c3b22f0a8396142e89037dd8b8eb2a94211f33a8b3c3a00add92b3a7a09e2850d5b06d0658a62ce41e47b032aa6ad24c7ce127676d8c892")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000dea417bbd7de15fbb5f2bc00618bb248f83304c70e50034ae43483f25804b099003a8979bf0995d97fe01bf095c5776a6da0bf3adc02f47b80e8f7aa9b663b5632")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000cc46182a887b2de7270ee55e7dd363b2f3e56c9384d2107e3528ba026e79af9d00646dc7ed94957c1466e792f118ddcfce6c6b1e560821cb91929192a80e2f83bc")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000c3ce6859a5812f36b84212e1970bf30b9f2281a6d13be56ba47381e7d9deae39005cacf6473c4cd8cfeb295e86527f9202ddfde8d310d0fe16c199380d479fc703")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f000034da1b3b1be617df647d4a7c1e5ffb47326e7f0a3c5f8a0031134eb33333ab7b006015bd86d4e90bcb6e4964020baafd7b967c0211d285a4aa2e78b0120efa8320")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000745cbbcccabfc7e40774a3cbf1376b544143c3e84962199d6498c108dd96e5680069378bb647354afdaf15037db142278d1d8d28289218094d74163c2d27a84c70")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f000048b39028a5076febd58398fc12e6c464432c1a5ba36471cbd974e2ccb50014fe00e178bba60f8f2fe3d627bd02ffbff6d5a3e8c8d6f58b70cdb7c45e886b504d74")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f00007fc9e991ff1156dc35d2c6b72f98e4928e05b9288766884f7a0d319a62276027008852fe5aed35fbe5cde2c0c3b7ab3d860a7d48ecee78516acb475a7a4b593985")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f00008e8f049533868b0e18729769749d65789e3f40451fa80b260bbdc5bb0314c74a00b35dbb96f371b493cce11ef28f320cd15b5d0c55ff4daa5fea46827dabe7c16c")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000b901b0426192a3cd85d234bf84b8ee5a9f71b78de2acfa7f4b08014052ab67f4002525ad1b9a8d1e4dcfa6233b21336792317c2ed8b030a72ce59991381b17ccf9")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000b8be53bc8d604f0b709a447eb56b9732b921474c52e6ed47103301dd2d089892007e8eca7416f12564248f27d34a2f984245a803a7ad76169681cd54eab9022cdf")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f0000d6cca4d5ebcb037d650bcb0a42bbeb35d5161a3dc8266c3aa6263aff714435b20034ca3238b4dce77c5e5a4284ae15cee765f5f0e830f5ae16438f2089ed4b3ab2")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f00004160393264d2ecfc2d30278733b74daf26b1f708f5851ef9815f237c752d89f5006d42c85805906391a6eaea123e683c7b4388a287197fde83abbc6f7bbbab4c48")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f7365727665722e6465762e6f6c7669642e696f00002602eab1695427d5338522a1ca97b42dbbe8ea46065cb4ed8ee7d358ab578db700a47337f389028d66364f1ec6a9db0cdc666bc62d950464af5362a54aed523e9f")!),
    ]
    
}


extension ObvContactIdentifier {
    
    // 20 samples
    @MainActor
    static let sampleDatas: [Self] = ObvCryptoId.sampleDatasForContactCryptoId.map { .init(contactCryptoId: $0, ownedCryptoId: .sampleOwnedCryptoId) }
        
}


extension String {

    @MainActor
    static let listOfFirstNames: [String] = ["Alice", "Amanda", "Anatole", "Bob", "Carol", "David", "Eve", "Frank", "Grace", "Henry", "Irene", "Jack",
                                             "Kate", "Lee", "Mark", "Nancy", "Oliver", "Penelope", "Quentin", "Rachel", "Simon", "Tina",
                                             "Ursula", "Victor", "Wendy", "Xenia", "Yvonne"]
    
    @MainActor
    static let listOfLastNames: [String] = ["Adams", "Baker", "Clark", "Davis", "Evans", "Fisher", "Garcia", "Hall", "Irwin", "Jackson",
                                            "King", "Lee", "Miller", "Nelson", "Owens", "Parker", "Quinn", "Reed", "Smith", "Taylor",
                                            "Upton", "Vaughn", "Walker", "Young", "York", "Zimmerman" ]
    
    @MainActor static func sampleGroupMemberNames(_ groupIdentifier: ObvGroupCellViewModel.GroupIdentifier) -> Self {
        let groupMembers = [
            "Emma Johnson, Liam Smith",
            "Olivia Williams, Noah Brown, Ava Jones",
            "James Garcia, Isabella Miller, Benjamin Davis, Sophia Rodriguez",
            "Mason Martinez, Mia Hernandez",
            "Ethan Lopez, Charlotte Gonzalez, Lucas Wilson, Amelia Anderson, Alexander Thomas",
            "Harper Taylor, Daniel Moore",
            "Evelyn Jackson, Henry Lee, Abigail White, Michael Harris",
            "Emily Clark, William Lewis",
            "Elizabeth Walker, Joseph Young, Sofia Hall, Samuel Allen",
            "Scarlett King, David Wright, Victoria Scott",
            "Jack Green, Grace Adams, Jackson Baker",
            "Chloe Nelson, Matthew Carter, Zoe Mitchell",
            "Christopher Perez, Lily Turner, Andrew Parker",
            "Emma Johnson, Olivia Williams, James Garcia",
            "Isabella Miller, Benjamin Davis, Sophia Rodriguez, Mason Martinez",
            "Mia Hernandez, Ethan Lopez, Charlotte Gonzalez",
            "Lucas Wilson, Amelia Anderson, Alexander Thomas, Harper Taylor",
            "Daniel Moore, Evelyn Jackson, Henry Lee",
            "Abigail White, Michael Harris, Emily Clark, William Lewis",
            "Elizabeth Walker, Joseph Young, Sofia Hall",
            "Samuel Allen, Scarlett King, David Wright"
        ]
        guard let index = ObvGroupCellViewModel.GroupIdentifier.sampleDatas.firstIndex(of: groupIdentifier) else { return "Unknown" }
        guard index < groupMembers.count else { return "Outofbounds" }
        return groupMembers[index]
    }
    
    @MainActor
    static func sampleFirstName(_ contactCryptoId: ObvCryptoId) -> Self {
        guard let index = ObvCryptoId.sampleDatasForContactCryptoId.firstIndex(of: contactCryptoId) else { return "Unknown" }
        guard index < listOfFirstNames.count else { return "Outofbounds" }
        return listOfFirstNames[index]
    }

    @MainActor
    static func sampleLastName(_ contactCryptoId: ObvCryptoId) -> Self {
        let names = ["Adams", "Baker", "Clark", "Davis", "Evans", "Fisher", "Garcia", "Hall", "Irwin", "Jackson",
                     "King", "Lee", "Miller", "Nelson", "Owens", "Parker", "Quinn", "Reed", "Smith", "Taylor",
                     "Upton", "Vaughn", "Walker", "Young", "York", "Zimmerman" ]
        guard let index = ObvCryptoId.sampleDatasForContactCryptoId.firstIndex(of: contactCryptoId) else { return "Unknown" }
        guard index < names.count else { return "Outofbounds" }
        return names[index]
    }

    @MainActor
    static func samplePosition(_ contactCryptoId: ObvCryptoId) -> Self {
        let positions = ["Accountant", "Brand Manager", "CEO", "Developer", "Engineer", "Finance Analyst", "Graphic Designer", "HR Manager", "Intern", "Janitor",
                         "Key Account Manager", "Lawyer", "Marketing Director", "Network Administrator", "Operations Manager", "Product Manager", "Quality Assurance", "Recruiter", "Sales Representative", "Technician",
                         "UX Designer", "Vice President", "Web Developer", "eXecutive Assistant", "Yield Manager", "Zoning Specialist"]
        guard let index = ObvCryptoId.sampleDatasForContactCryptoId.firstIndex(of: contactCryptoId) else { return "Unknown" }
        guard index < positions.count else { return "Outofbounds" }
        return positions[index]
    }

    @MainActor
    static func sampleCompany(_ contactCryptoId: ObvCryptoId) -> Self {
        let fakeCompanies = [
            "Apex Dynamics", "Blue Horizon", "Crimson Tech", "DataSphere", "Eclipse Systems",
            "Fusion Works", "Global Ventures", "Horizon Labs", "Infinite Solutions", "Jupiter Networks",
            "Kinetix Media", "Luminary Apps", "Matrix Innovations", "Nebula Corp", "Omni Industries",
            "Pinnacle Group", "Quantum Soft", "Radiant Designs", "Stellar Systems", "Terra Firms"
        ]
        guard let index = ObvCryptoId.sampleDatasForContactCryptoId.firstIndex(of: contactCryptoId) else { return "Unknown" }
        guard index < fakeCompanies.count else { return "Outofbounds" }
        return fakeCompanies[index]
    }

    @MainActor
    static func sampleFirstLetter(_ contactCryptoId: ObvCryptoId) -> Self {
        return String(String.sampleFirstName(contactCryptoId).first ?? Character("#"))
    }
    
    @MainActor
    static func sampleGroupName(_ groupIdentifier: ObvCells.ObvGroupCellViewModel.GroupIdentifier) -> Self {
        let fakeGroupNames = [
            "Tech Enthusiasts", "Bookworms United", "Fitness Fanatics", "Gaming Legends",
            "Foodie Adventures", "Travel Buddies", "Movie Buffs", "Music Lovers",
            "Art & Creativity", "Pet Lovers Club", "Coding Gurus", "Hiking Explorers",
            "Photography Pros", "DIY Masters", "Parenting Tips", "Car Enthusiasts",
            "Science Geeks", "Fashionistas", "History Buffs", "Chess Champions"
        ]
        guard let index = ObvCells.ObvGroupCellViewModel.GroupIdentifier.sampleDatas.firstIndex(of: groupIdentifier) else { return "Unknown" }
        guard index < fakeGroupNames.count else { return "Outofbounds" }
        return fakeGroupNames[index]
    }
    
}

extension ObvGroupV2.Identifier {

    // 20 samples
    @MainActor
    static var sampleDatas: [Self] = UID.sampleDatas.map { .init(groupUID: $0, serverURL: URL(string: "https://olvid.io")!, category: .server) }
    
}

extension ObvGroupV2Identifier {
    
    // 20 samples
    @MainActor
    static var sampleDatas: [Self] = ObvGroupV2.Identifier.sampleDatas.map { .init(ownedCryptoId: .sampleOwnedCryptoId, identifier: $0) }
    
}


extension ObvDiscussionIdentifier {
    
    // 20 samples, one per sample contact identifier
    @MainActor
    static var sampleDatasForOneToOne: [ObvDiscussionIdentifier] = ObvContactIdentifier.sampleDatas.map { .oneToOne(id: $0) }
    
    // 20 samples
    @MainActor
    static var sampleDatasForGroupV2: [ObvDiscussionIdentifier] = ObvGroupV2Identifier.sampleDatas.map { .groupV2(id: $0) }

    // 40 samples
    @MainActor
    static var sampleDatas: [ObvDiscussionIdentifier] = (sampleDatasForOneToOne + sampleDatasForGroupV2).shuffled()
    
}

private extension ObvAvatarViewModel.Colors {
    
    @MainActor
    static var sampleDatas: [Self] = [
        .init(foreground: .systemBlue,
              background: .systemRed),
        .init(foreground: .systemPink,
              background: .systemCyan),
    ]
    
}

public extension ObvAvatarViewModel {
    
    @MainActor
    static func sampleData(_ contactCryptoId: ObvCryptoId) -> Self {
        let character = String.sampleFirstLetter(contactCryptoId)
        return .init(characterOrIcon: .character(character.first!),
                     colors: Colors.sampleDatas[0],
                     photoURL: nil)
    }
    
    @MainActor
    static func sampleData(_ groupIdentifier: ObvGroupCellViewModel.GroupIdentifier) -> Self {
        let firstLetterOfGroupName = String.sampleGroupName(groupIdentifier).first!
        return .init(characterOrIcon: .character(firstLetterOfGroupName), colors: Colors.sampleDatas[1], photoURL: nil)
    }
    
    
    @MainActor
    static let sampleData: Self = .init(characterOrIcon: .character("X"), colors: Colors.sampleDatas[0], photoURL: nil)
    
}

public extension URL {
    
    @MainActor
    static var sampleInvitationURL: Self = URL(string: "https://invitation.olvid.io/#AwAAAHkAAAAAWmh0dHBzOi8vc2VydmVyLm9sdmlkLmlvAACNP6iKSLqQv_UgmZtgs8EDx3D013uY-C5dVHnvQfwXoAEAdoB6mDCwbnCC-zKSWACnrGkwFr3xvHL2qbSoEvml_AAAAAAVTWF0aGlldSBMYW5veSAoT2x2aWQp")!
    
    
    @MainActor static let photoURLs: [URL] = [
        URL(string: "https://dev.olvid.io/avatar00")!,
        URL(string: "https://dev.olvid.io/avatar01")!,
        URL(string: "https://dev.olvid.io/avatar02")!,
        URL(string: "https://dev.olvid.io/avatar03")!,
        URL(string: "https://dev.olvid.io/avatar04")!,
        URL(string: "https://dev.olvid.io/avatar05")!,
        URL(string: "https://dev.olvid.io/avatar06")!,
    ]

    
}

extension SharingProfileViewModel {
    
    @MainActor
    static var sampleDatas: [Self] = [
        .init(fullName: "John Doe", role: "Product Manager @ Olvid", urlIdentityRepresentation: URL.sampleInvitationURL, avatarModel: ObvAvatarViewModel.sampleData, scanStep: .noScan),
        .init(fullName: "John Doe", role: "Product Manager @ Olvid", urlIdentityRepresentation: URL.sampleInvitationURL, avatarModel: ObvAvatarViewModel.sampleData, scanStep: .firstScan)
    ]
    
}

extension ObvGroupIdentifier {
    
    // 20 samples
    @MainActor
    static var sampleDatas: [Self] = ObvGroupV2Identifier.sampleDatas.map { .groupV2($0) }
    
}


extension InvitationContactsListViewModel {
    
    @MainActor
    static var sampleDatasForLocalContacts: Self = {
        var contactIdentifiersForKey: [String: [ContactIdentifier]] = [:]
        for contactIdentifier in ObvContactIdentifier.sampleDatas {
            let firstLetter = String.sampleFirstLetter(contactIdentifier.contactCryptoId)
            var contactIdentifiers: [ContactIdentifier] = contactIdentifiersForKey[firstLetter] ?? []
            contactIdentifiers.append(.obvContactIdentifier(contactIdentifier))
            contactIdentifiersForKey[firstLetter] = contactIdentifiers
        }
        return .init(contactIdentifiers: contactIdentifiersForKey,
                     numberOfMissingResults: 0)
    }()
 
    @MainActor
    static var sampleDatasForKeycloakUsers: Self = {
        var contactIdentifiersForKey: [String: [ContactIdentifier]] = [:]
        for contactIdentifier in ObvContactIdentifier.sampleDatas {
            let firstLetter = String.sampleFirstLetter(contactIdentifier.contactCryptoId)
            var contactIdentifiers: [ContactIdentifier] = contactIdentifiersForKey[firstLetter] ?? []
            contactIdentifiers.append(.obvContactIdentifier(contactIdentifier))
            contactIdentifiersForKey[firstLetter] = contactIdentifiers
        }
        return .init(contactIdentifiers: contactIdentifiersForKey,
                     numberOfMissingResults: 42)
    }()

    
    @MainActor
    func filterSampleDatas(searchStatus: InvitationContactsListViewModel.SearchStatus) -> Self {
        switch searchStatus {
            
        case .notPerformingSearch:
            return self
            
        case .performingSearch(let searchText):
            if let searchText, !searchText.isEmpty {
                var contactIdentifiers = self.contactIdentifiers
                for (key, value) in contactIdentifiers {
                    let filteredValue = value.filter { contactIdentifier in
                        switch contactIdentifier {
                        case .obvContactIdentifier(let obvContactIdentifier):
                            let contactCryptoId = obvContactIdentifier.contactCryptoId
                            let firstName = String.sampleFirstName(contactCryptoId)
                            let lastName = String.sampleLastName(contactCryptoId)
                            let position = String.samplePosition(contactCryptoId)
                            let company = String.sampleCompany(contactCryptoId)
                            let all = [firstName, lastName, position, company].joined(separator: " ")
                            return all.contains(searchText)
                        case .keycloakContactIdentifier:
                            return false
                        case .persistedObvContactIdentity(_):
                            return false
                        }
                    }
                    if filteredValue.isEmpty {
                        contactIdentifiers.removeValue(forKey: key)
                    } else {
                        contactIdentifiers[key] = filteredValue
                    }
                }
                let filteredViewModel: InvitationContactsListViewModel = .init(
                    contactIdentifiers: contactIdentifiers,
                    numberOfMissingResults: 0)
                return filteredViewModel
            } else {
                return self
            }
            
        }
        
    }
    
}

extension ObvCells.ObvGroupCellViewModel.GroupIdentifier {
    
    @MainActor
    static let sampleDatas: [Self] = ObvGroupIdentifier.sampleDatas.map { .obvGroupIdentifier($0) }
    
}

extension InvitationFlowGroupListViewModel {
    
    // 20 group identifiers in the model
    @MainActor
    static let sampleData: Self = {
        return .init(groupIdentifiers: ObvCells.ObvGroupCellViewModel.GroupIdentifier.sampleDatas)
    }()
    
    @MainActor
    func filterSampleDatas(searchStatus: InvitationFlowGroupListViewModel.SearchStatus) -> Self {
        switch searchStatus {

        case .notPerformingSearch:
            return self
        case .performingSearch(let searchText):
            if let searchText, !searchText.isEmpty {
                
                let groupIdentifiers = self.groupIdentifiers
                var filteredGroupIdentifiers = [ObvGroupCellViewModel.GroupIdentifier]()
                for groupIdentifier in groupIdentifiers {
                    let groupName = String.sampleGroupName(groupIdentifier)
                    let groupMembers = String.sampleGroupMemberNames(groupIdentifier)
                    if groupName.contains(searchText) || groupMembers.contains(searchText) {
                        filteredGroupIdentifiers.append(groupIdentifier)
                    }
                }
                
                return .init(groupIdentifiers: filteredGroupIdentifiers)
                
            } else {
                return self
            }
            
        }
    }
    
}


extension ObvGroupCellViewModel {
    
    @MainActor
    static func sampleData(groupIdentifier: ObvCells.ObvGroupCellViewModel.GroupIdentifier) -> Self {
        .init(groupIdentifier: .sampleDatas[0],
              avatarModel: .sampleData(groupIdentifier),
              title: String.sampleGroupName(groupIdentifier),
              listOfGroupMemberNames: String.sampleGroupMemberNames(groupIdentifier),
              showGreenShield: false,
              hasUpdatedDetails: .noNewPublishedDetails,
              updateInProgress: false)
    }
    
}

extension InvitationContactsListViewModel.ContactIdentifier {
    
    // 20 samples
    @MainActor
    static var sampleDatasForLocalContacts: [Self] = ObvContactIdentifier.sampleDatas.map { .obvContactIdentifier($0) }
        
}


extension InvitationContactsListCellView.Model {
    
    
    @MainActor
    static func sampleData(_ contactIdentifier: InvitationContactsListViewModel.ContactIdentifier) -> Self {
        switch contactIdentifier {
        case .obvContactIdentifier(let obvContactIdentifier):
            let avatarModel = ObvAvatarViewModel.sampleData(obvContactIdentifier.contactCryptoId)
            let firstName = String.sampleFirstName(obvContactIdentifier.contactCryptoId)
            let lastName = String.sampleLastName(obvContactIdentifier.contactCryptoId)
            let position: String? = String.samplePosition(obvContactIdentifier.contactCryptoId)
            let company: String? = String.sampleCompany(obvContactIdentifier.contactCryptoId)
            let isKeycloakManaged = false
            let coreDetails = ObvIdentityCoreDetails.withAcceptableDefaults(
                firstName: firstName,
                lastName: lastName,
                company: company,
                position: position,
                signedUserDetails: nil)
            return .init(avatarModel: avatarModel,
                         coreDetails: coreDetails,
                         customDisplayName: nil,
                         isKeycloakManaged: isKeycloakManaged,
                         wasRecentlyOnline: true,
                         contactsSortOrder: .byFirstName)
        case .keycloakContactIdentifier(let obvKeycloakUserDetails, _):
            let avatarModel = ObvAvatarViewModel.sampleData
            let coreDetails = ObvIdentityCoreDetails.withAcceptableDefaults(
                firstName: obvKeycloakUserDetails.firstName ?? "Firstname",
                lastName: obvKeycloakUserDetails.lastName ?? "Lastname",
                company: nil,
                position: nil,
                signedUserDetails: nil)
            return .init(avatarModel: avatarModel,
                         coreDetails: coreDetails,
                         customDisplayName: nil,
                         isKeycloakManaged: true,
                         wasRecentlyOnline: true,
                         contactsSortOrder: .byFirstName)
        case .persistedObvContactIdentity:
            assertionFailure("Unexpected in previews")
            return .init(avatarModel: ObvAvatarViewModel.sampleData,
                         coreDetails: ObvIdentityCoreDetails.withAcceptableDefaults(
                            firstName: "firstName",
                            lastName: "lastName",
                            company: "company",
                            position: "position",
                            signedUserDetails: nil),
                         customDisplayName: "customDisplayName",
                         isKeycloakManaged: false,
                         wasRecentlyOnline: true,
                         contactsSortOrder: .byFirstName)
        }
    }
    
}


extension ScanValidationViewModel {

    @MainActor
    static var sampleDatas: [Self] = [
        .init(contactStatus: .contactNotAddedYet,
              contactAvatarModel: ObvAvatarViewModel.sampleData(ObvCryptoId.sampleDatasForContactCryptoId[0]),
              contactFullDisplayName: "Abel Dorwart",
              contactIdentifier: .init(contactCryptoId: ObvCryptoId.sampleDatasForContactCryptoId[0], ownedCryptoId: .sampleOwnedCryptoId)),
        .init(contactStatus: .contactAdded(activeOneToOneDiscussionAvailable: true, contactFirstName: "Abel"),
              contactAvatarModel: ObvAvatarViewModel.sampleData(ObvCryptoId.sampleDatasForContactCryptoId[0]),
              contactFullDisplayName: "Abel Dorwart",
              contactIdentifier: .init(contactCryptoId: ObvCryptoId.sampleDatasForContactCryptoId[0], ownedCryptoId: .sampleOwnedCryptoId)),
    ]
    
}

extension ContactInvitationViewModel {
    
    @MainActor
    static func sampleData(_ contactIdentifier: ContactInvitationViewModel.ContactIdentifier) -> Self {
        
        switch contactIdentifier {
        case .obvContactIdentifier(let obvContactIdentifier, let keycloakUserDetails):
            let contactCryptoId = obvContactIdentifier.contactCryptoId
            let title = [String.sampleFirstName(contactCryptoId), String.sampleLastName(contactCryptoId)].joined(separator: " ")
            let subtitle = [String.samplePosition(contactCryptoId), " @ ", String.sampleCompany(contactCryptoId)].joined()
            return .init(avatarModel: .sampleData(obvContactIdentifier.contactCryptoId),
                         isKeycloakManaged: keycloakUserDetails != nil,
                         title: title,
                         subtitle: subtitle,
                         inviteHasBeenSent: false,
                         groupsAvatarModel: [],
                         groupTitle: "Group title",
                         isOneToOne: false)
        }
        
    }
    
}


extension ObvURLIdentity {
    
    @MainActor
    static let sampleDataOwnedIdentity: Self = .init(
        cryptoId: ObvCryptoId.sampleOwnedCryptoId,
        fullDisplayName: "Alice Wonderland")

    @MainActor
    static let sampleDataRemoteIdentity: Self = .init(
        cryptoId: ObvCryptoId.sampleDatasForContactCryptoId[0],
        fullDisplayName: "Bob Leponge")
    
}


extension ObvTypes.ObvMutualScanUrl {
    
    @MainActor
    static let sampleData: Self = .init(
        cryptoId: .sampleOwnedCryptoId,
        fullDisplayName: "Alice Wonderland",
        signature: Data(repeating: 0, count: 0))

    
}


//extension ContactInvitationViewModel {
//    
//    @MainActor
//    static var sampleDatas: [Self] = [
//        .init(avatarModel: ObvAvatarViewModel.sampleData,
//              isKeycloakManaged: true,
//              title: "Abel Dorwart",
//              subtitle: "ne fait pas parti de vos contacts",
//              inviteHasBeenSent: false,
//              groupsAvatarModel: [
//                ObvAvatarViewModel.sampleDatas[0],
//                ObvAvatarViewModel.sampleDatas[1],
//                ObvAvatarViewModel.sampleDatas[2],
//                ObvAvatarViewModel.sampleDatas[3],
//                ObvAvatarViewModel.sampleDatas[4],
//                ObvAvatarViewModel.sampleDatas[5],
//                ObvAvatarViewModel.sampleDatas[6]
//              ],
//              groupTitle: "Ski 2025 et 2 autres groupes en commun",
//              confirmDialogTitle: "",
//              isOneToOne: false),
//        .init(avatarModel: ObvAvatarViewModel.sampleDatas[1], isKeycloakManaged: true, title: "Anne-Marie Dorwart", subtitle: "ne fait pas parti de vos contacts", inviteHasBeenSent: false, groupsAvatarModel: [
//            ObvAvatarViewModel.sampleDatas[0],
//        ], groupTitle: "Ski 2025 et 2 autres groupes en commun",
//              confirmDialogTitle: "",
//              isOneToOne: false),
//        .init(avatarModel: ObvAvatarViewModel.sampleDatas[2], isKeycloakManaged: true, title: "Benjamin Dorwart", subtitle: "ne fait pas parti de vos contacts", inviteHasBeenSent: false, groupsAvatarModel: [
//            ObvAvatarViewModel.sampleDatas[0],
//            ObvAvatarViewModel.sampleDatas[1],
//            ObvAvatarViewModel.sampleDatas[2],
//            ObvAvatarViewModel.sampleDatas[3],
//        ], groupTitle: "Ski 2025 et 2 autres groupes en commun",
//              confirmDialogTitle: "",
//              isOneToOne: false),
//        .init(avatarModel: ObvAvatarViewModel.sampleDatas[3], isKeycloakManaged: true, title: "Boris Dorwart", subtitle: "ne fait pas parti de vos contacts", inviteHasBeenSent: false, groupsAvatarModel: [
//            ObvAvatarViewModel.sampleDatas[0],
//            ObvAvatarViewModel.sampleDatas[1],
//        ], groupTitle: "Ski 2025 et 2 autres groupes en commun",
//              confirmDialogTitle: "",
//              isOneToOne: false),
//        .init(avatarModel: ObvAvatarViewModel.sampleDatas[4], isKeycloakManaged: true, title: "Mathias Dorwart", subtitle: "ne fait pas parti de vos contacts", inviteHasBeenSent: false, groupsAvatarModel: [
//            ObvAvatarViewModel.sampleDatas[0],
//            ObvAvatarViewModel.sampleDatas[1],
//            ObvAvatarViewModel.sampleDatas[2],
//            ObvAvatarViewModel.sampleDatas[3],
//            ObvAvatarViewModel.sampleDatas[4],
//        ], groupTitle: "Ski 2025 et 2 autres groupes en commun",
//              confirmDialogTitle: "",
//              isOneToOne: false),
//        .init(avatarModel: ObvAvatarViewModel.sampleDatas[5], isKeycloakManaged: true, title: "Jean Dorwart", subtitle: "ne fait pas parti de vos contacts", inviteHasBeenSent: false, groupsAvatarModel: [
//            ObvAvatarViewModel.sampleDatas[0],
//            ObvAvatarViewModel.sampleDatas[1],
//            ObvAvatarViewModel.sampleDatas[5],
//            ObvAvatarViewModel.sampleDatas[6]
//        ], groupTitle: "Ski 2025 et 2 autres groupes en commun",
//              confirmDialogTitle: "",
//              isOneToOne: false),
//        .init(avatarModel: ObvAvatarViewModel.sampleDatas[6], isKeycloakManaged: true, title: "Jeanne Dorwart", subtitle: "ne fait pas parti de vos contacts", inviteHasBeenSent: false, groupsAvatarModel: [
//            ObvAvatarViewModel.sampleDatas[0],
//            ObvAvatarViewModel.sampleDatas[1],
//            ObvAvatarViewModel.sampleDatas[2],
//            ObvAvatarViewModel.sampleDatas[3],
//            ObvAvatarViewModel.sampleDatas[4],
//            ObvAvatarViewModel.sampleDatas[5],
//            ObvAvatarViewModel.sampleDatas[6]
//        ], groupTitle: "Ski 2025 et 2 autres groupes en commun",
//              confirmDialogTitle: "",
//              isOneToOne: false),
//    ]
//}
