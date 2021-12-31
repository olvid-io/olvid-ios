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

public typealias SuiteVersion = Int

public class ObvCryptoSuite {

    // MARK: Singleton pattern
    public static let sharedInstance: ObvCryptoSuite = ObvCryptoSuite()
    
    public let latestVersion: SuiteVersion
    public let minAcceptableVersion: SuiteVersion
    
    private let concretePRNGs: [SuiteVersion: ConcretePRNG.Type]
    private let prngServices: [SuiteVersion: PRNGService.Type]
    private let authenticatedEncryptionPrimitives: [SuiteVersion: AuthenticatedEncryptionConcrete.Type]
    private let kdfPrimitives: [SuiteVersion: KDF.Type]
    private let proofOfWorkEngines: [SuiteVersion: ProofOfWorkEngine.Type]
    private let authentications: [SuiteVersion: AuthenticationConcrete.Type]
    private let hashFunctions: [SuiteVersion: HashFunction.Type]
    private let commitmentSchemes: [SuiteVersion: Commitment.Type]
    private let macs: [SuiteVersion: MACConcrete.Type]
    
    private let defaultPublicKeyEncryptionImplementationByteId: [SuiteVersion: PublicKeyEncryptionImplementationByteId]
    private let defaultAuthenticationImplementationByteId: [SuiteVersion: AuthenticationImplementationByteId]
    
    init() {
        latestVersion = 0
        minAcceptableVersion = 0
        concretePRNGs = [0: PRNGWithHMACWithSHA256.self]
        prngServices = [0: PRNGServiceWithHMACWithSHA256.self]
        authenticatedEncryptionPrimitives = [0: AuthenticatedEncryptionWithAES256CTRThenHMACWithSHA256.self]
        kdfPrimitives = [0: KDFFromPRNGWithHMACWithSHA256.self]
        proofOfWorkEngines = [0: ProofOfWorkEngineSyndromeBased.self]
        authentications = [0: AuthenticationFromSignatureOnMDC.self]
        hashFunctions = [0: SHA256.self]
        commitmentSchemes = [0: CommitmentWithSHA256.self]
        defaultPublicKeyEncryptionImplementationByteId = [0: .KEM_ECIES_Curve25519_and_DEM_CTR_AES_256_then_HMAC_SHA_256]
        defaultAuthenticationImplementationByteId = [0: .Signature_with_EC_SDSA_with_MDC]
        macs = [0: HMACWithSHA256.self]
    }
    
    // PRNG
    
    public func concretePRNG(forSuiteVersion version: SuiteVersion) -> ConcretePRNG.Type? {
        return concretePRNGs[version]
    }
    
    public func concretePRNG() -> ConcretePRNG.Type {
        return concretePRNG(forSuiteVersion: latestVersion)!
    }
    
    // PRNG Service
    
    func prngService(forSuiteVersion version: SuiteVersion) -> PRNGService? {
        return prngServices[version]?.sharedInstance
    }
    
    public func prngService() -> PRNGService {
        return prngService(forSuiteVersion: latestVersion)!
    }
    
    // Authenticated encryption
    
    public func authenticatedEncryption(forSuiteVersion version: SuiteVersion) -> AuthenticatedEncryptionConcrete.Type? {
        return authenticatedEncryptionPrimitives[version]
    }

    public func authenticatedEncryption() -> AuthenticatedEncryptionConcrete.Type {
        return authenticatedEncryption(forSuiteVersion: latestVersion)!
    }
    
    // KDF
    
    func kdf(forSuiteVersion version: SuiteVersion) -> KDF.Type? {
        return kdfPrimitives[version]
    }
    
    public func kdf() -> KDF.Type {
        return kdf(forSuiteVersion: latestVersion)!
    }
    
    // Proof of Work
    
    func proofOfWorkEngine(forSuiteVersion version: SuiteVersion) -> ProofOfWorkEngine.Type? {
        return proofOfWorkEngines[version]
    }
    
    public func proofOfWorkEngine() -> ProofOfWorkEngine.Type {
        return proofOfWorkEngine(forSuiteVersion: latestVersion)!
    }

    // Authentication
    
    func authentication(forSuiteVersion version: SuiteVersion) -> AuthenticationConcrete.Type? {
        return authentications[version]
    }

    public func authentication() -> AuthenticationConcrete.Type {
        return authentication(forSuiteVersion: latestVersion)!
    }
    
    // Hash function
    
    public func hashFunction(forSuiteVersion version: SuiteVersion) -> HashFunction.Type? {
        return hashFunctions[version]
    }
    
    func hashFunction() -> HashFunction.Type {
        return hashFunction(forSuiteVersion: latestVersion)!
    }
    
    public func hashFunctionSha256() -> HashFunction.Type {
        return SHA256.self
    }
    
    // Commitment scheme
    
    func commitmentScheme(forSuiteVersion version: SuiteVersion) -> Commitment.Type? {
        return commitmentSchemes[version]
    }
    
    public func commitmentScheme() -> Commitment.Type {
        return commitmentScheme(forSuiteVersion: latestVersion)!
    }
    
    // Default PublicKeyEncryptionImplementationByteId and AuthenticationImplementationByteId
    
    func getDefaultPublicKeyEncryptionImplementationByteId(forSuiteVersion version: SuiteVersion) -> PublicKeyEncryptionImplementationByteId? {
        return defaultPublicKeyEncryptionImplementationByteId[version]
    }

    public func getDefaultPublicKeyEncryptionImplementationByteId() -> PublicKeyEncryptionImplementationByteId {
        return getDefaultPublicKeyEncryptionImplementationByteId(forSuiteVersion: latestVersion)!
    }

    func getDefaultAuthenticationImplementationByteId(forSuiteVersion version: SuiteVersion) -> AuthenticationImplementationByteId? {
        return defaultAuthenticationImplementationByteId[version]
    }
    
    public func getDefaultAuthenticationImplementationByteId() -> AuthenticationImplementationByteId {
        return getDefaultAuthenticationImplementationByteId(forSuiteVersion: latestVersion)!
    }
    
    // MAC scheme
    
    public func mac(forSuiteVersion version: SuiteVersion) -> MACConcrete.Type? {
        return macs[version]
    }
    
    public func mac() -> MACConcrete.Type {
        return mac(forSuiteVersion: latestVersion)!
    }
}
