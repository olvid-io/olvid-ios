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
import ObvCrypto
import ObvTypes
import ObvEncoder

public struct GroupInformation {

    public let groupOwnerIdentity: ObvCryptoIdentity
    public let groupUid: UID
    public let groupDetailsElements: GroupDetailsElements
    public let serializedGroupDetailsElements: Data

    public var raw: Data {
        return groupOwnerIdentity.getIdentity() + groupUid.raw
    }

    public init(groupOwnerIdentity: ObvCryptoIdentity, groupUid: UID, groupDetailsElements: GroupDetailsElements) throws {
        self.groupOwnerIdentity = groupOwnerIdentity
        self.groupUid = groupUid
        self.groupDetailsElements = groupDetailsElements
        self.serializedGroupDetailsElements = try groupDetailsElements.encode()
    }

    
    public var associatedProtocolUid: UID {
        let prngType = ObvCryptoSuite.sharedInstance.concretePRNG()
        let rawSeed = groupOwnerIdentity.getIdentity() + groupUid.raw
        let seed = Seed(with: rawSeed)!
        let prng = prngType.init(with: seed)
        return UID.gen(with: prng)
    }
    
    public static func createDummyGroupInformation(groupOwnerIdentity: ObvCryptoIdentity, groupUid: UID) throws -> GroupInformation {
        let dummyGroupCoreDetails = ObvGroupCoreDetails(name: "", description: nil)
        let dummyGroupDetailsElements = GroupDetailsElements(version: 0, coreDetails: dummyGroupCoreDetails, photoServerKeyAndLabel: nil)
        let dummyGroupInformation = try GroupInformation(groupOwnerIdentity: groupOwnerIdentity, groupUid: groupUid, groupDetailsElements: dummyGroupDetailsElements)
        return dummyGroupInformation
    }
 
    public func withPhotoServerKeyAndLabel(_ photoServerKeyAndLabel: PhotoServerKeyAndLabel?) throws -> GroupInformation {
        try GroupInformation(groupOwnerIdentity: self.groupOwnerIdentity, groupUid: self.groupUid, groupDetailsElements: self.groupDetailsElements.withPhotoServerKeyAndLabel(photoServerKeyAndLabel))
    }
}

extension GroupInformation: ObvCodable {

    public func encode() -> ObvEncoded {
        return [self.groupOwnerIdentity, self.groupUid, self.serializedGroupDetailsElements].encode()
    }


    public init?(_ encoded: ObvEncoded) {
        do {
            (groupOwnerIdentity, groupUid, serializedGroupDetailsElements) = try encoded.decode()
            groupDetailsElements = try GroupDetailsElements(serializedGroupDetailsElements)
        } catch {
            return nil
        }
    }

}


extension GroupInformation: Hashable {

    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.groupOwnerIdentity)
        hasher.combine(self.groupUid)
    }

}



/// This structure is used to return information from the identity manager. It shall not be used to send information to it.
/// This allows to make sure that the photoURL is internal to the engine.
public struct GroupInformationWithPhoto {

    public let groupInformation: GroupInformation
    public let photoURL: URL?
    
    
    public init(groupOwnerIdentity: ObvCryptoIdentity, groupUid: UID, groupDetailsElements: GroupDetailsElements, photoURL: URL?) throws {
        self.groupInformation = try GroupInformation(groupOwnerIdentity: groupOwnerIdentity, groupUid: groupUid, groupDetailsElements: groupDetailsElements)
        self.photoURL = photoURL
    }

    public init(groupInformation: GroupInformation, photoURL: URL?) {
        self.groupInformation = groupInformation
        self.photoURL = photoURL
    }

    public var associatedProtocolUid: UID {
        groupInformation.associatedProtocolUid
    }

    public var groupUid: UID {
        groupInformation.groupUid
    }

    public var groupOwnerIdentity: ObvCryptoIdentity {
        groupInformation.groupOwnerIdentity
    }

    public var groupDetailsElementsWithPhoto: GroupDetailsElementsWithPhoto {
        GroupDetailsElementsWithPhoto(groupDetailsElements: groupInformation.groupDetailsElements, photoURL: photoURL)
    }
    
    public func withPhotoServerKeyAndLabel(_ photoServerKeyAndLabel: PhotoServerKeyAndLabel?) throws -> GroupInformationWithPhoto {
        let newGroupInformation = try self.groupInformation.withPhotoServerKeyAndLabel(photoServerKeyAndLabel)
        return GroupInformationWithPhoto(groupInformation: newGroupInformation, photoURL: self.photoURL)
    }
}


extension GroupInformationWithPhoto: ObvCodable {

    public func encode() -> ObvEncoded {
        if let photoURL = self.photoURL {
            return [groupInformation, photoURL].encode()
        } else {
            return [groupInformation].encode()
        }
    }

    public init?(_ encoded: ObvEncoded) {
        guard let encodedElements = [ObvEncoded](encoded) else { assertionFailure(); return nil }
        switch encodedElements.count {
        case 1:
            guard let groupInformation = GroupInformation(encodedElements[0]) else { assertionFailure(); return nil }
            self.init(groupInformation: groupInformation, photoURL: nil)
        case 2:
            guard let groupInformation = GroupInformation(encodedElements[0]) else { assertionFailure(); return nil }
            guard let photoURL = URL(encodedElements[1]) else { assertionFailure(); return nil }
            self.init(groupInformation: groupInformation, photoURL: photoURL)
        default:
            assertionFailure()
            return nil
        }
    }

}
