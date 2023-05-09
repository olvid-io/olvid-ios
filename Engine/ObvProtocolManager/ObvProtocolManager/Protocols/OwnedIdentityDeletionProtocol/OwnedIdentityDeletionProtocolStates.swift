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
import ObvEncoder
import ObvTypes
import ObvCrypto
import ObvMetaManager


// MARK: - Protocol States

extension OwnedIdentityDeletionProtocol {
    
    enum StateId: Int, ConcreteProtocolStateId {
        
        case initialState = 0
        case deletionCurrentStatus = 1
        case final = 100

        var concreteProtocolStateType: ConcreteProtocolState.Type {
            switch self {
            case .initialState          : return ConcreteProtocolInitialState.self
            case .deletionCurrentStatus : return DeletionCurrentStatusState.self
            case .final                 : return FinalState.self
            }
        }
    }
    
    
    // MARK: - DeletionCurrentStatusState
    
    struct DeletionCurrentStatusState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.deletionCurrentStatus
        let notifyContacts: Bool
        let otherProtocolInstancesHaveBeenProcessed: Bool
        let groupsV1HaveBeenProcessed: Bool
        let groupsV2HaveBeenProcessed: Bool
        let contactsHaveBeenProcessed: Bool
        let channelsHaveBeenProcessed: Bool

        init(notifyContacts: Bool) {
            self.init(notifyContacts: notifyContacts, otherProtocolInstancesHaveBeenProcessed: false, groupsV1HaveBeenProcessed: false, groupsV2HaveBeenProcessed: false, contactsHaveBeenProcessed: false, channelsHaveBeenProcessed: false)
        }
        
        private init(notifyContacts: Bool, otherProtocolInstancesHaveBeenProcessed: Bool, groupsV1HaveBeenProcessed: Bool, groupsV2HaveBeenProcessed: Bool, contactsHaveBeenProcessed: Bool, channelsHaveBeenProcessed: Bool) {
            self.notifyContacts = notifyContacts
            self.otherProtocolInstancesHaveBeenProcessed = otherProtocolInstancesHaveBeenProcessed
            self.groupsV1HaveBeenProcessed = groupsV1HaveBeenProcessed
            self.groupsV2HaveBeenProcessed = groupsV2HaveBeenProcessed
            self.contactsHaveBeenProcessed = contactsHaveBeenProcessed
            self.channelsHaveBeenProcessed = channelsHaveBeenProcessed
        }

        func obvEncode() -> ObvEncoded {
            [notifyContacts,
             otherProtocolInstancesHaveBeenProcessed,
             groupsV1HaveBeenProcessed,
             groupsV2HaveBeenProcessed,
             contactsHaveBeenProcessed,
             channelsHaveBeenProcessed].obvEncode()
        }
        
        init(_ obvEncoded: ObvEncoded) throws {
            guard let encodedValues = [ObvEncoded](obvEncoded, expectedCount: 6) else { assertionFailure(); throw Self.makeError(message: "Unexpected number of elements in encoded DeletionCurrentStatusState") }
            self.notifyContacts = try encodedValues[0].obvDecode()
            self.otherProtocolInstancesHaveBeenProcessed = try encodedValues[1].obvDecode()
            self.groupsV1HaveBeenProcessed = try encodedValues[2].obvDecode()
            self.groupsV2HaveBeenProcessed = try encodedValues[3].obvDecode()
            self.contactsHaveBeenProcessed = try encodedValues[4].obvDecode()
            self.channelsHaveBeenProcessed = try encodedValues[5].obvDecode()
        }
        
        func getStateWhenOtherProtocolInstancesHaveBeenProcessed() -> DeletionCurrentStatusState {
            DeletionCurrentStatusState(
                notifyContacts: notifyContacts,
                otherProtocolInstancesHaveBeenProcessed: true,
                groupsV1HaveBeenProcessed: groupsV1HaveBeenProcessed,
                groupsV2HaveBeenProcessed: groupsV2HaveBeenProcessed,
                contactsHaveBeenProcessed: contactsHaveBeenProcessed,
                channelsHaveBeenProcessed: channelsHaveBeenProcessed
            )
        }

        func getStateWhenGroupsV1HaveBeenProcessed() -> DeletionCurrentStatusState {
            DeletionCurrentStatusState(
                notifyContacts: notifyContacts,
                otherProtocolInstancesHaveBeenProcessed: otherProtocolInstancesHaveBeenProcessed,
                groupsV1HaveBeenProcessed: true,
                groupsV2HaveBeenProcessed: groupsV2HaveBeenProcessed,
                contactsHaveBeenProcessed: contactsHaveBeenProcessed,
                channelsHaveBeenProcessed: channelsHaveBeenProcessed
            )
        }

        func getStateWhenGroupsV2HaveBeenProcessed() -> DeletionCurrentStatusState {
            DeletionCurrentStatusState(
                notifyContacts: notifyContacts,
                otherProtocolInstancesHaveBeenProcessed: otherProtocolInstancesHaveBeenProcessed,
                groupsV1HaveBeenProcessed: groupsV1HaveBeenProcessed,
                groupsV2HaveBeenProcessed: true,
                contactsHaveBeenProcessed: contactsHaveBeenProcessed,
                channelsHaveBeenProcessed: channelsHaveBeenProcessed
            )
        }

        func getStateWhenContactsHaveBeenProcessed() -> DeletionCurrentStatusState {
            DeletionCurrentStatusState(
                notifyContacts: notifyContacts,
                otherProtocolInstancesHaveBeenProcessed: otherProtocolInstancesHaveBeenProcessed,
                groupsV1HaveBeenProcessed: groupsV1HaveBeenProcessed,
                groupsV2HaveBeenProcessed: groupsV2HaveBeenProcessed,
                contactsHaveBeenProcessed: true,
                channelsHaveBeenProcessed: channelsHaveBeenProcessed
            )
        }

        func getStateWhenChannelsHaveBeenProcessed() -> DeletionCurrentStatusState {
            DeletionCurrentStatusState(
                notifyContacts: notifyContacts,
                otherProtocolInstancesHaveBeenProcessed: otherProtocolInstancesHaveBeenProcessed,
                groupsV1HaveBeenProcessed: groupsV1HaveBeenProcessed,
                groupsV2HaveBeenProcessed: groupsV2HaveBeenProcessed,
                contactsHaveBeenProcessed: contactsHaveBeenProcessed,
                channelsHaveBeenProcessed: true
            )
        }

    }

    
    // MARK: - FinalState
    
    struct FinalState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.final
        
        init(_: ObvEncoded) {}
        
        init() {}
        
        func obvEncode() -> ObvEncoded { return 0.obvEncode() }
        
    }
    
}
