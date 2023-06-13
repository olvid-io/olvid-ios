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
import ObvCrypto
import LocalAuthentication
import UIKit
import ObvUICoreData

enum VerifyPasscodeResult {
    case valid
    case lockedOut
    case wrong(passcodeAttemptCountWasIncremented: Bool)
}

enum LocalAuthenticationResult {
    case authenticated(authenticationWasPerformed: Bool)
    case cancelled
    case lockedOut
}

protocol VerifyPasscodeDelegate: AnyObject {
    var remainingLockoutTime: TimeInterval? { get async }
    var isLockedOut: Bool { get async }

    func verifyPasscode(_ candidate: String, firstTryForThisSession: Bool) async -> VerifyPasscodeResult
}

protocol CreatePasscodeDelegate: AnyObject {
    func clearPasscode() async
    func savePasscode(_ passcode: String, passcodeIsPassword: Bool) async throws
    func requestCustomPasscode(viewController: UIViewController) async -> LocalAuthenticationResult
}

protocol LocalAuthenticationDelegate: AnyObject {
    var remainingLockoutTime: TimeInterval? { get async }
    var isLockedOut: Bool { get async }

    func performLocalAuthentication(viewController: UIViewController, uptimeAtTheTimeOfChangeoverToNotActiveState: TimeInterval?, localizedReason: String) async -> LocalAuthenticationResult
}


// MARK: - LocalAuthenticationManager

final actor LocalAuthenticationManager: LocalAuthenticationDelegate, VerifyPasscodeDelegate, CreatePasscodeDelegate {

    private static let pinSaltByteLength = 8

    func performPostInitialization() async {
        self.cleanPreviousLockoutUptime()
    }

    private func cleanPreviousLockoutUptime() {
        guard let lockoutUptime = ObvMessengerSettings.Privacy.lockoutUptime else {
            return
        }
        if TimeInterval.getUptime() < lockoutUptime {
            // This means that the device has been rebooted.
            // There is an avantage if the rebooting time is smaller than ObvMessengerConstants.lockOutDuration. But we consider that rebooting the device to make three more attempts prevents brute-force attacks.
            // Since the stored lockoutUptime is in the future, we clear it to avoid to be locked out for no good reason.
            ObvMessengerSettings.Privacy.lockoutUptime = nil
        }

        if lockoutUptime + ObvMessengerConstants.lockOutDuration < TimeInterval.getUptime() {
            // The stored lockOutDuration corresponds the a past lock-out, we can clear it.
            ObvMessengerSettings.Privacy.lockoutUptime = nil
        }
    }

    private var lastCandidate: String? = nil
    private var isDeleting: Bool = false

    var timeIntervalSinceLockout: TimeInterval? {
        guard let lockoutUptime = ObvMessengerSettings.Privacy.lockoutUptime else {
            return nil
        }
        guard lockoutUptime <= TimeInterval.getUptime() else {
            return nil
        }
        return TimeInterval.getUptime() - lockoutUptime
    }

    var remainingLockoutTime: TimeInterval? {
        guard let timeIntervalSinceLockout = timeIntervalSinceLockout else {
            return nil
        }
        guard timeIntervalSinceLockout < ObvMessengerConstants.lockOutDuration else {
            return nil
        }
        return ObvMessengerConstants.lockOutDuration - timeIntervalSinceLockout
    }

    var isLockedOut: Bool {
        guard let timeIntervalSinceLockout = timeIntervalSinceLockout else {
            return false
        }
        return timeIntervalSinceLockout < ObvMessengerConstants.lockOutDuration
    }

    func savePasscode(_ passcode: String, passcodeIsPassword: Bool) throws {
        let prng = ObvCryptoSuite.sharedInstance.prngService()
        let salt = prng.genBytes(count: Self.pinSaltByteLength)
        let hash = try self.computePasscodeHash(passcode, salt: salt)
        ObvMessengerSettings.Privacy.passcodeHashAndSalt = (hash, salt)
        ObvMessengerSettings.Privacy.passcodeIsPassword = passcodeIsPassword
    }

    func performLocalAuthentication(viewController: UIViewController, uptimeAtTheTimeOfChangeoverToNotActiveState: TimeInterval?, localizedReason: String) async -> LocalAuthenticationResult {
        let result = await self.internalPerformLocalAuthentication(viewController: viewController, uptimeAtTheTimeOfChangeoverToNotActiveState: uptimeAtTheTimeOfChangeoverToNotActiveState, localizedReason: localizedReason)
        switch result {
        case .authenticated:
            ObvMessengerSettings.Privacy.userHasBeenLockedOut = false
        case .cancelled, .lockedOut:
            break
        }
        return result
    }

    private func internalPerformLocalAuthentication(viewController: UIViewController, uptimeAtTheTimeOfChangeoverToNotActiveState: TimeInterval?, localizedReason: String) async -> LocalAuthenticationResult {
        guard !isLockedOut else {
            return .lockedOut
        }
        let userIsAlreadyAuthenticated: Bool
        if ObvMessengerSettings.Privacy.userHasBeenLockedOut {
            // The app or an extension has been locked, we want to be sure to restart authentification regardless of the grace period. UserHasBeenLockedOut holds util next authentication.
            userIsAlreadyAuthenticated = false
        } else if let uptimeAtTheTimeOfChangeoverToNotActiveState {
            let timeIntervalSinceLastChangeoverToNotActiveState = TimeInterval.getUptime() - uptimeAtTheTimeOfChangeoverToNotActiveState
            assert(0 <= timeIntervalSinceLastChangeoverToNotActiveState)
            userIsAlreadyAuthenticated = (timeIntervalSinceLastChangeoverToNotActiveState < ObvMessengerSettings.Privacy.lockScreenGracePeriod)
        } else {
            userIsAlreadyAuthenticated = false
        }
        guard !userIsAlreadyAuthenticated else {
            return .authenticated(authenticationWasPerformed: false)
        }
        switch ObvMessengerSettings.Privacy.localAuthenticationPolicy {
        case .none:
            return .authenticated(authenticationWasPerformed: false)
        case .deviceOwnerAuthentication:
            let laContext = LAContext()
            var error: NSError?
            laContext.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
            guard error == nil else {
                if error!.code == LAError.Code.passcodeNotSet.rawValue {
                    return .authenticated(authenticationWasPerformed: false)
                }
                return .cancelled
            }
            do {
                try await laContext.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: localizedReason)
                return .authenticated(authenticationWasPerformed: true)
            } catch {
                return .cancelled
            }
        case .biometricsWithCustomPasscodeFallback:
            let laContext = LAContext()
            var error: NSError?
            guard laContext.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
                return await requestCustomPasscode(viewController: viewController)
            }
            do {
                try await laContext.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: localizedReason)
                return .authenticated(authenticationWasPerformed: true)
            } catch {
                return await requestCustomPasscode(viewController: viewController)
            }
        case .customPasscode:
            return await requestCustomPasscode(viewController: viewController)
        }
    }

    func requestCustomPasscode(viewController: UIViewController) async -> LocalAuthenticationResult {
        let passcodeViewController = await VerifyPasscodeViewController(verifyPasscodeDelegate: self)
        await viewController.present(passcodeViewController, animated: true)
        switch await passcodeViewController.getResult() {
        case .succeed:
            return .authenticated(authenticationWasPerformed: true)
        case .lockedOut:
            return .lockedOut
        case .cancelled:
            return .cancelled
        }
    }

    func verifyPasscode(_ candidate: String, firstTryForThisSession: Bool) -> VerifyPasscodeResult {
        if self.isLockedOut {
            return .lockedOut
        }
        if internalVerifyPasscode(candidate) {
            lastCandidate = nil
            isDeleting = false
            resetPasscodeFailedCount()
            return .valid
        }
        // Used to generate an haptic error.
        var passcodeAttemptCountWasIncremented = false
        if let lastCandidate = lastCandidate {
            if lastCandidate == candidate {
                // Nothing to do
            } else if lastCandidate.isSubchain(of: candidate) { /// Last AB, Current ABC
                self.isDeleting = false
                if firstTryForThisSession {
                    ObvMessengerSettings.Privacy.passcodeAttempsSessions += 1
                }
            } else if candidate.isSubchain(of: lastCandidate) { /// Last ABC, Current AB
                if self.isDeleting {
                    // Nothing to do
                } else {
                    ObvMessengerSettings.Privacy.passcodeFailedCount += 1
                    passcodeAttemptCountWasIncremented = true
                    self.isDeleting = true
                }
            } else {
                ObvMessengerSettings.Privacy.passcodeFailedCount += 1
                passcodeAttemptCountWasIncremented = true
                self.isDeleting = false
            }
        }

        if ObvMessengerSettings.Privacy.passcodeAttemptCount >= ObvMessengerConstants.allowedNumberOfWrongPasscodesBeforeLockOut {
            ObvMessengerSettings.Privacy.passcodeFailedCount = 0
            ObvMessengerSettings.Privacy.passcodeAttempsSessions = 0
            ObvMessengerSettings.Privacy.lockoutUptime = TimeInterval.getUptime()
            ObvMessengerSettings.Privacy.userHasBeenLockedOut = true
            return .lockedOut
        } else {
            self.lastCandidate = candidate
            return .wrong(passcodeAttemptCountWasIncremented: passcodeAttemptCountWasIncremented)
        }
    }


    private func resetPasscodeFailedCount() {
        ObvMessengerSettings.Privacy.passcodeFailedCount = 0
        ObvMessengerSettings.Privacy.passcodeAttempsSessions = 0
        ObvMessengerSettings.Privacy.lockoutUptime = nil
    }

    func clearPasscode() {
        ObvMessengerSettings.Privacy.passcodeHashAndSalt = nil
        resetPasscodeFailedCount()
    }

    // Whether the given passcode is correct, e.g. equals to the hash of the passcode store in user default.
    private func internalVerifyPasscode(_ passcode: String) -> Bool {
        if let (passcodeHash, passcodeSalt) = ObvMessengerSettings.Privacy.passcodeHashAndSalt {
            do {
                let hash = try computePasscodeHash(passcode, salt: passcodeSalt)
                return hash == passcodeHash
            } catch {
                assertionFailure()
                return false
            }
        } else {
            return true
        }
    }

    private func computePasscodeHash(_ passcode: String, salt: Data) throws -> Data {
        return try PBKDF.pbkdf2sha256(password: passcode, salt: salt, rounds: 1000, derivedKeyLength: 160)
    }
}

fileprivate extension String {

    /// Return true if self is an ordered subset of given string
    /// “abc” is a subchain of “XXaYYbZZZc123”
    /// “abc” is a subchain of “XXaYYbbbbZZZc123”
    /// “” is a subchain of “XXaYYbZZZc123”
    /// “abc” is not a subchain of “XXbYYaZZZc123”
    func isSubchain(of string: String) -> Bool {
        var array = Array(string)

        for char in self {
            guard let idx = array.firstIndex(of: char) else {
                return false
            }
            array = Array(array[(idx+1)...])
        }

        return true
    }

}
