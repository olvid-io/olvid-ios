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


public protocol PRNGService: PRNG {
    static var sharedInstance: PRNGService { get }
}


public class PRNGServiceWithHMACWithSHA256: PRNGService {
    
    // MARK: Singleton pattern (part of the PRNGService protocol)
    
    public static let sharedInstance: PRNGService = PRNGServiceWithHMACWithSHA256()
    
    // MARK: Initializing the internal PRNG
    
    private var prng: ConcretePRNG = {
        let seed = Seed.generateFromSecRandomCopyBytes()
        return PRNGWithHMACWithSHA256(with: seed)
    }()
    
    private var reseedCounter: UInt64 = 1 // Number of calls to genBytes(count:) since instantiation or reseeding
    private let reseedInterval: UInt64 = 100

    // MARK: Initializing the serial dispatch queue on which we execute requests for random bytes

    private let queue = DispatchQueue(label: "io.olvid.prngServiceWithHMACWithSHA256", qos: DispatchQoS.userInitiated)
    
    // MARK: Implementing the (rest of the) PRNGService protocol
    
    // MARK: Implementing the PRNG protocol, required by the PRNG service protocol
    
    public func genBytes(count: Int) -> Data {
        queue.sync {
            if reseedCounter > reseedInterval {
                let seed = Seed.generateFromSecRandomCopyBytes()
                prng.reseed(with: seed)
                reseedCounter = 1
            }
        }
        var randomBytes = Data()
        queue.sync {
            randomBytes = prng.genBytes(count: count)
            reseedCounter += 1
        }
        assert(randomBytes.count == count)
        return randomBytes
    }

    
}
