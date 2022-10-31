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
    func reseed(with: Seed) throws
}


public class PRNGServiceWithHMACWithSHA256: PRNGService {
    
    // MARK: Singleton pattern (part of the PRNGService protocol)
    
    public static let sharedInstance: PRNGService = PRNGServiceWithHMACWithSHA256()
    
    // MARK: Initializing the internal PRNG
    
    private var prng: PRNG =  {
        let seedBytes = UnsafeMutablePointer<UInt8>.allocate(capacity: Seed.minLength)
        defer { seedBytes.deallocate() }
        let res = SecRandomCopyBytes(kSecRandomDefault, Seed.minLength, seedBytes)
        guard res == errSecSuccess else { exit(-1) }
        let rawSeed = Data(bytes: seedBytes, count: Seed.minLength)
        let seed = Seed(with: rawSeed)!
        return PRNGWithHMACWithSHA256(with: seed)
    }()
    
    // MARK: Initializing the serial dispatch queue on which we execute requests for random bytes

    private let queue = DispatchQueue(label: "io.olvid.prngServiceWithHMACWithSHA256", qos: DispatchQoS.userInitiated)
    
    // MARK: Implementing the (rest of the) PRNGService protocol
    
    public func reseed(with seed: Seed) {
        let _prng = PRNGWithHMACWithSHA256(with: seed)
        queue.sync {
            prng = _prng
        }
    }
    
    // MARK: Implementing the PRNG protocol, required by the PRNG service protocol
    
    public func genBytes(count: Int) -> Data {
        var randomBytes = Data()
        queue.sync {
            randomBytes = prng.genBytes(count: count)
        }
        assert(randomBytes.count == count)
        return randomBytes
    }

    
}
