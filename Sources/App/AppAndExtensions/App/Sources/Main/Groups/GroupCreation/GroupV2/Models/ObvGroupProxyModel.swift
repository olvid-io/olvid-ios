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

import Foundation
import UniformTypeIdentifiers
import ObvUICoreData
import ObvTypes
import ObvUIObvCircledInitials


final class ObvGroupProxyModel {
    
    private(set) var selectedUsers = Set<PersistedUser>() // Selected users among the group members
    private(set) var admins = Set<PersistedUser>()
    private(set) var groupName: String?
    private(set) var groupDescription: String?
    private(set) var groupPicture: (image: UIImage, url: URL, isTemporary: Bool)?
    private(set) var groupTypeValue: GroupTypeValue?
    
    private let groupIdentifier: Data?
    private let directoryForTempFiles: URL
    
    var groupType: PersistedGroupV2.GroupType? {
        guard let groupTypeValue else { return nil }
        return savedGroupTypeForValue[groupTypeValue, default: defaultGroupTypeForValue(groupTypeValue)]
    }
    
    var coreDetails: GroupV2CoreDetails {
        .init(groupName: groupName, groupDescription: groupDescription)
    }
    
    var circledInitialsConfiguration: CircledInitialsConfiguration? {
        guard let image = groupPicture?.image else { return nil }
        return CircledInitialsConfiguration.groupV2(photo: .image(image: image), groupIdentifier: groupIdentifier ?? Data(), showGreenShield: false)
    }
    
    var parametersOfAdvancedType: (isReadOnly: Bool, policy: PersistedGroupV2.GroupType.RemoteDeleteAnythingPolicy) {
        let groupType = savedGroupTypeForValue[.advanced, default: defaultGroupTypeForValue(.advanced)]
        switch groupType {
        case .standard, .managed, .readOnly:
            assertionFailure("This is a bug")
            return (false, .nobody)
        case .advanced(isReadOnly: let isReadOnly, remoteDeleteAnythingPolicy: let remoteDeleteAnythingPolicy):
            return (isReadOnly, remoteDeleteAnythingPolicy)
        }
    }
    
    let editOrCreate: GroupInfoViewEditOrCreate
    
    private var savedGroupTypeForValue = [GroupTypeValue: PersistedGroupV2.GroupType]()
    
    private func defaultGroupTypeForValue(_ value: GroupTypeValue) -> PersistedGroupV2.GroupType {
        switch value {
        case .standard:
            return .standard
        case .managed:
            return .managed
        case .readOnly:
            return .readOnly
        case .advanced:
            return .advanced(isReadOnly: false, remoteDeleteAnythingPolicy: .nobody)
        }
    }
    
    
    @MainActor
    init(ownedCryptoId: ObvCryptoId, editionType: NewGroupEditionFlowViewController.EditionType, directoryForTempFiles: URL) {
                
        self.directoryForTempFiles = directoryForTempFiles
        
        switch editionType {
            
        case .createGroup:
            // Nothing to do, the groupProxyModel is already set
            self.groupIdentifier = nil
            self.groupPicture = nil
            self.groupTypeValue = .standard // On creation, pre-select the standard group
            self.editOrCreate = .create
            return
            
        case .modifyGroup(delegate: _, groupIdentifier: let groupIdentifier):
            self.editOrCreate = .edit
            self.groupIdentifier = groupIdentifier
            guard let group = try? PersistedGroupV2.getWithPrimaryKey(ownCryptoId: ownedCryptoId, groupIdentifier: groupIdentifier, within: ObvStack.shared.viewContext) else {
                assertionFailure()
                return
            }
            self.selectedUsers = Set(group.otherMembers.compactMap({groupMember in
                do {
                    if let contact = groupMember.contact {
                        return try PersistedUser(contact: contact)
                    } else {
                        return try PersistedUser(groupMember: groupMember)
                    }
                } catch {
                    assertionFailure()
                    return nil
                }
            }))
            self.admins = Set(group.otherMembers.filter { $0.isAnAdmin }.compactMap { try? $0.asPersistedUser })
            self.groupName = group.trustedName
            self.groupDescription = group.trustedDescription
            if let photoURL = group.trustedPhotoURL, let photoData = try? Data(contentsOf: photoURL), let photo = UIImage(data: photoData) {
                self.groupPicture = (photo, photoURL, false)
            } else {
                self.groupPicture = nil
            }
            if let groupType = group.getAdequateGroupType() {
                self.savedGroupTypeForValue[groupType.value] = groupType
                self.groupTypeValue = groupType.value
            }
            
        case .cloneGroup(delegate: _, initialGroupMembers: let initialGroupMembers, initialGroupName: let initialGroupName, initialGroupDescription: let initialGroupDescription, initialPhotoURL: let initialPhotoURL, initialGroupType: let initialGroupType):
            
            self.editOrCreate = .create
            self.groupIdentifier = nil
            
            var selectedGroupMembers = Array<PersistedUser>()
            var admins = Set<PersistedUser>()
            
            for member in initialGroupMembers {
                if let contact = try? PersistedObvContactIdentity.get(contactCryptoId: member.cryptoId, ownedIdentityCryptoId: ownedCryptoId, whereOneToOneStatusIs: .any, within: ObvStack.shared.viewContext), contact.supportsCapability(.groupsV2),
                 let user = try? PersistedUser(contact: contact)  {
                    selectedGroupMembers.append(user)
                    if member.isAdmin { admins.insert(user) }
                } else {
                    assertionFailure()
                }
            }

            self.selectedUsers = Set(selectedGroupMembers)
            self.admins = admins
            self.groupName = initialGroupName
            self.groupDescription = initialGroupDescription
            if let photoURL = initialPhotoURL, let photoData = try? Data(contentsOf: photoURL), let photo = UIImage(data: photoData) {
                self.groupPicture = (photo, photoURL, false)
            } else {
                self.groupPicture = nil
            }
            if let initialGroupType {
                self.savedGroupTypeForValue[initialGroupType.value] = initialGroupType
                self.groupTypeValue = initialGroupType.value
            }
            
        }
    }
    

    @MainActor
    func setSelectedUsers(to newSelectedUsers: Set<PersistedUser>) {
        self.selectedUsers = newSelectedUsers
        self.admins = self.admins.intersection(newSelectedUsers)
    }

    
    @MainActor
    func setGroupTypeValue(to newGroupTypeValue: GroupTypeValue) {
        self.groupTypeValue = newGroupTypeValue
    }

    
    @MainActor
    func changeUserAdminStatus(userCryptoId: ObvTypes.ObvCryptoId, isAdmin: Bool) {
        guard let user = selectedUsers.first(where: { $0.cryptoId == userCryptoId }) else { assertionFailure(); return }
        if isAdmin {
            admins.insert(user)
        } else {
            admins.remove(user)
        }
    }
    
    
    func setIsReadOnly(to newIsReadOnly: Bool) {
        guard let groupType else { assertionFailure(); return }
        switch groupType {
        case .standard, .managed, .readOnly:
            assertionFailure()
            return
        case .advanced(isReadOnly: _, remoteDeleteAnythingPolicy: let remoteDeleteAnythingPolicy):
            savedGroupTypeForValue[.advanced] = .advanced(isReadOnly: newIsReadOnly, remoteDeleteAnythingPolicy: remoteDeleteAnythingPolicy)
        }
    }
    
    
    func setRemoteDeleteAnythingPolicy(to newPolicy: PersistedGroupV2.GroupType.RemoteDeleteAnythingPolicy) {
        guard let groupType else { assertionFailure(); return }
        switch groupType {
        case .standard, .managed, .readOnly:
            assertionFailure()
            return
        case .advanced(isReadOnly: let isReadOnly, remoteDeleteAnythingPolicy: _):
            savedGroupTypeForValue[.advanced] = .advanced(isReadOnly: isReadOnly, remoteDeleteAnythingPolicy: newPolicy)
        }
    }
    
    @MainActor
    func setGroupInfos(name: String?, description: String?, photo: UIImage?) {
        self.groupName = name
        self.groupDescription = description
        
        if photo != self.groupPicture?.image {
            
            if let photo, let photoURL = Self.saveImage(image: photo, inDirectoryForTempFiles: directoryForTempFiles) {
                if let currentGroupPicture = self.groupPicture, currentGroupPicture.isTemporary {
                    try? FileManager.default.removeItem(at: currentGroupPicture.url)
                }
                self.groupPicture = (photo, photoURL, true)
            } else {
                self.groupPicture = nil
            }
            
        }
    }
        
    
    fileprivate static func saveImage(image: UIImage, inDirectoryForTempFiles directoryForTempFiles: URL) -> URL? {
        
        guard let jpegData = image.jpegData(compressionQuality: 1.0) else { assertionFailure(); return nil }
        
        let filename = [UUID().uuidString, UTType.jpeg.preferredFilenameExtension ?? "jpeg"].joined(separator: ".")
        let filepath = directoryForTempFiles.appendingPathComponent(filename)
        do {
            try jpegData.write(to: filepath)
            return filepath
        } catch {
            assertionFailure()
            return nil
        }
        
    }

}
