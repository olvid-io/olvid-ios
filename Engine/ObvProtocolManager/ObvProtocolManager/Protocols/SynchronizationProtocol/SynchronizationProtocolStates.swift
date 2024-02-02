/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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

extension SynchronizationProtocol {
    
    enum StateId: Int, ConcreteProtocolStateId {
        
        case initial = 0
        // case ongoingSyncSnapshot = 1
        case final = 100
        
        var concreteProtocolStateType: ConcreteProtocolState.Type {
            switch self {
            case .initial : return ConcreteProtocolInitialState.self
            // case .ongoingSyncSnapshot: return OngoingSyncSnapshotState.self
            case .final   : return FinalState.self
            }
        }
    }
    
    
    // MARK: - OngoingSyncState
    
//    struct OngoingSyncSnapshotState: TypeConcreteProtocolState {
//        
//        let id: ConcreteProtocolStateId = StateId.ongoingSyncSnapshot
//        
//        let otherOwnedDeviceUid: UID
//        let localSnapshot: ObvSyncSnapshotAndVersion
//        let remoteSnapshot: ObvSyncSnapshotAndVersion?
//        let currentlyShowingDiff: Bool
//        
//        init(otherOwnedDeviceUid: UID, localSnapshot: ObvSyncSnapshotAndVersion, remoteSnapshot: ObvSyncSnapshotAndVersion?, currentlyShowingDiff: Bool) {
//            self.otherOwnedDeviceUid = otherOwnedDeviceUid
//            self.localSnapshot = localSnapshot
//            self.remoteSnapshot = remoteSnapshot
//            self.currentlyShowingDiff = currentlyShowingDiff
//        }
//
//        public func obvEncode() throws -> ObvEncoder.ObvEncoded {
//            var arrayOfEncoded = [
//                otherOwnedDeviceUid.obvEncode(),
//                try localSnapshot.obvEncode(),
//                currentlyShowingDiff.obvEncode(),
//            ]
//            
//            if let remoteSnapshot {
//                arrayOfEncoded.append(try remoteSnapshot.obvEncode())
//            }
//            
//            return arrayOfEncoded.obvEncode()
//        }
//
//        
//        init(_ obvEncoded: ObvEncoded) throws {
//            guard let arrayOfEncoded = [ObvEncoded](obvEncoded) else {
//                throw ObvError.couldNotDecode
//            }
//            switch arrayOfEncoded.count {
//            case 3:
//                (otherOwnedDeviceUid, localSnapshot, currentlyShowingDiff) = try obvEncoded.obvDecode()
//                remoteSnapshot = nil
//            case 4:
//                (otherOwnedDeviceUid, localSnapshot, currentlyShowingDiff, remoteSnapshot) = try obvEncoded.obvDecode()
//            default:
//                throw ObvError.couldNotDecode
//            }
//        }
//                
//        enum ObvError: Error {
//            case couldNotDecode
//        }
//
//    }
    
    
    // MARK: - FinalState
    
    struct FinalState: TypeConcreteProtocolState {
        
        let id: ConcreteProtocolStateId = StateId.final
        
        init(_: ObvEncoded) {}
        
        init() {}
        
        func obvEncode() -> ObvEncoded { return 0.obvEncode() }
        
    }
    
}
