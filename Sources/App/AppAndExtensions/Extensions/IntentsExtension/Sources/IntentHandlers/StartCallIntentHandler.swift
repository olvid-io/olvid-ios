/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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

import Intents
import OSLog
import AVFoundation
import ObvUICoreData
import ObvTypes
import ObvAppCoreConstants


/// Handles `INStartCallIntent` within the Intents extension.
///
/// **Intent lifecycle**
/// 1. ``resolveCallCapability(for:)`` — normalises the call type to audio (Olvid always starts calls as audio).
/// 2. ``resolveContacts(for:)`` — identifies the callees. Each contact in the intent is resolved
///    independently via ``resolveContact(_:)``. If Siri already carries an Olvid `customIdentifier`
///    (e.g. from a previous call donation), the contact is verified against the database so stale
///    donations are caught early. Otherwise the extension performs a display-name search and either
///    returns the unique match or asks Siri to disambiguate.
/// 3. ``confirm(intent:)`` — validates the resolved intent and returns `.ready` so that Siri
///    proceeds to the handle step.
/// 4. ``handle(intent:)`` — returns `.continueInApp`, which causes Siri to open the main app.
///    The app receives the intent in `SceneDelegate.scene(_:continue:)` and initiates the call.
final class StartCallIntentHandler: NSObject, INStartCallIntentHandling {

    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "StartCallIntentHandler")


    func resolveCallCapability(for intent: INStartCallIntent) async -> INStartCallCallCapabilityResolutionResult {
        Self.logger.info("📞🏁 Resolving call capability for INStartCallIntent")
        // Olvid always starts calls as audio; video can be added mid-call via the in-call UI.
        return .success(with: .audioCall)
    }


    func resolveContacts(for intent: INStartCallIntent) async -> [INStartCallContactResolutionResult] {

        Self.logger.info("📞🏁 Resolving \(intent.contacts?.count ?? 0) contacts for INStartCallIntent")

        let contacts = intent.contacts ?? []

        guard !contacts.isEmpty else {
            Self.logger.info("📞 No contacts provided, needs value")
            return [.needsValue()]
        }

        var results: [INStartCallContactResolutionResult] = []
        for contact in contacts {
            results.append(await resolveContact(contact))
        }
        
        Self.logger.info("📞 Returning \(results.count) results")
        
        return results

    }


    /// Validates the resolved intent before ``handle(intent:)`` is called.
    ///
    /// Checks (in order):
    /// 1. All resolved contacts carry a parseable `ObvContactIdentifier` and belong to the same
    ///    owned profile.
    /// 2. Microphone permission is already granted — extensions cannot request it interactively.
    /// 3. Every contact exists in the database and has at least one device (channel); without a
    ///    channel the call cannot be set up.
    /// 4. The owned identity (or any sibling profile) has the `canCall` API permission.
    ///
    /// Returning `.failure` here surfaces a CarPlay error message to the user before the app is
    /// launched, which is preferable to silently failing inside the app.
    func confirm(intent: INStartCallIntent) async -> INStartCallIntentResponse {
        Self.logger.info("📞🏁 Confirming INStartCallIntent")

        // 1. Parse contacts and verify they all belong to the same profile.
        var contactIdentifiers: [ObvContactIdentifier] = []
        for contact in intent.contacts ?? [] {
            guard let identifier = contact.customIdentifier else {
                Self.logger.error("📞 A resolved contact is missing its customIdentifier")
                return INStartCallIntentResponse(code: .failure, userActivity: nil)
            }
            guard let contactIdentifier = ObvContactIdentifier(identifier) else {
                Self.logger.error("📞 customIdentifier could not be parsed as ObvContactIdentifier")
                return INStartCallIntentResponse(code: .failure, userActivity: nil)
            }
            contactIdentifiers.append(contactIdentifier)
        }
        guard !contactIdentifiers.isEmpty else {
            Self.logger.error("📞 No contacts to call")
            return INStartCallIntentResponse(code: .failure, userActivity: nil)
        }
        let ownedCryptoIds = Set(contactIdentifiers.map(\.ownedCryptoId))
        guard ownedCryptoIds.count == 1 else {
            Self.logger.error("📞 The selected contacts span \(ownedCryptoIds.count) profiles")
            return INStartCallIntentResponse(code: .failure, userActivity: nil)
        }
        let ownedCryptoId = ownedCryptoIds.first!
        Self.logger.info("📞 \(contactIdentifiers.count) contact(s) all belong to the same profile")

        // 2. Microphone permission — cannot be requested from an extension.
        guard AVAudioSession.sharedInstance().recordPermission == .granted else {
            Self.logger.error("📞 Microphone permission not granted")
            return INStartCallIntentResponse(code: .failure, userActivity: nil)
        }

        // 3. Contacts exist in DB and have at least one device (channel).
        // 4. Owned identity has the canCall permission.
        do {
            let result = try await withCheckedThrowingContextualContinuation { (continuation: CheckedContinuation<INStartCallIntentResponse, any Error>, context) in
                for contactIdentifier in contactIdentifiers {
                    guard let contact = try PersistedObvContactIdentity.get(
                        contactCryptoId: contactIdentifier.contactCryptoId,
                        ownedIdentityCryptoId: ownedCryptoId,
                        whereOneToOneStatusIs: .any,
                        within: context) else {
                        Self.logger.error("📞 Contact not found in database")
                        return continuation.resume(returning: INStartCallIntentResponse(code: .failureContactNotSupportedByApp, userActivity: nil))
                    }
                    guard !contact.devices.isEmpty else {
                        Self.logger.error("📞 Contact has no device — no channel available")
                        return continuation.resume(returning: INStartCallIntentResponse(code: .failureContactNotSupportedByApp, userActivity: nil))
                    }
                }
                guard let ownedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: ownedCryptoId, within: context) else {
                    Self.logger.error("📞 Owned identity not found in database")
                    return continuation.resume(returning: INStartCallIntentResponse(code: .failure, userActivity: nil))
                }
                guard ownedIdentity.ownedCryptoIdAllowedToEmitSecureCall != nil else {
                    Self.logger.error("📞 No owned identity with canCall permission")
                    return continuation.resume(returning: INStartCallIntentResponse(code: .failureCallingServiceNotAvailable, userActivity: nil))
                }
                continuation.resume(returning: INStartCallIntentResponse(code: .ready, userActivity: nil))
            }
            if result.code == .ready {
                Self.logger.info("📞 All checks passed, returning .ready")
            }
            return result
        } catch {
            Self.logger.fault("📞 confirm failed: \(error)")
            return INStartCallIntentResponse(code: .failure, userActivity: nil)
        }

    }


    /// Executes the intent by asking Siri to open the main app.
    ///
    /// Returns `.continueInApp`, which causes the system to launch (or foreground) the main app
    /// and deliver the intent to `SceneDelegate.scene(_:continue:)`, where the actual call is
    /// initiated. The extension itself never places calls.
    func handle(intent: INStartCallIntent) async -> INStartCallIntentResponse {
        Self.logger.info("📞🏁 Handling INStartCallIntent")
        return INStartCallIntentResponse(code: .continueInApp, userActivity: nil)
    }
    
}


// MARK: - Private helpers

extension StartCallIntentHandler {
    
    /// Resolves a single contact from a voice-initiated call intent.
    ///
    /// This method is only ever called by SiriKit during voice interactions. CarPlay taps skip the
    /// resolution phase entirely and go straight to `confirm` → `handle`.
    ///
    /// **Why the identifier source determines `.success` vs `.confirmationRequired`**
    ///
    /// SiriKit calls `resolveContacts` repeatedly until every contact reaches `.success`. After the
    /// user confirms a `.confirmationRequired` result, Siri copies the `customIdentifier` from the
    /// returned `INPerson` directly onto `contact.customIdentifier` in the next pass. We use this to
    /// distinguish the two passes without extra state:
    ///
    /// - `contact.customIdentifier` set → second pass (user already confirmed) → return `.success`.
    /// - Only `contact.siriMatches?.first?.customIdentifier` set → first pass from INVocabulary →
    ///   return `.confirmationRequired` so the user gets a verbal "call X?" check.
    /// - No identifier at all → display-name search, which always returns `.confirmationRequired`.
    private func resolveContact(_ contact: INPerson) async -> INStartCallContactResolutionResult {

        // Track whether confirmation is still needed based on where the identifier came from.
        let customId: String?
        let needsConfirmation: Bool
        if let id = contact.customIdentifier {
            customId = id
            needsConfirmation = false   // second pass: user already confirmed
        } else if let id = contact.siriMatches?.first?.customIdentifier {
            customId = id
            needsConfirmation = true    // first pass: Siri matched via INVocabulary
        } else {
            customId = nil
            needsConfirmation = true
        }

        if let customId {
            Self.logger.info("📞 Contact has customIdentifier (needsConfirmation=\(needsConfirmation)), verifying against database")
            guard let contactIdentifier = ObvContactIdentifier(customId) else {
                Self.logger.error("📞 customIdentifier could not be parsed as ObvContactIdentifier for '\(contact.displayName, privacy: .private)', falling back to display-name search")
                return await resolveContactByDisplayName(contact)
            }
            do {
                // .oneToOne: call donations are made for one-to-one contacts; absent one-to-one falls through to display-name search.
                guard let inPerson = try await PersistedObvContactIdentity.getContactAsINPerson(contactIdentifier: contactIdentifier, whereOneToOneStatusIs: .oneToOne) else {
                    Self.logger.error("📞 Contact '\(contact.displayName, privacy: .private)' no longer exists in database, falling back to display-name search")
                    return await resolveContactByDisplayName(contact)
                }
                if needsConfirmation {
                    Self.logger.info("📞 Contact verified in database, returning confirmationRequired")
                    return .confirmationRequired(with: inPerson)
                } else {
                    Self.logger.info("📞 Contact verified in database, returning success")
                    return .success(with: inPerson)
                }
            } catch {
                Self.logger.fault("📞 Failed to verify contact '\(contact.displayName, privacy: .private)' in database: \(error), falling back to display-name search")
                return await resolveContactByDisplayName(contact)
            }
        }

        Self.logger.info("📞 Contact has no customIdentifier, falling back to display-name search")
        return await resolveContactByDisplayName(contact)

    }


    /// Searches the contact database for a display-name match.
    ///
    /// The search query is `contact.displayName`, falling back to
    /// `contact.siriMatches?.first?.displayName` when the top-level one is empty (Siri occasionally
    /// hands us an empty `displayName` and parks the actual recognized phrase on a Siri match).
    /// When neither carries a non-empty string, returns `.unsupported(.noContactFound)` rather than
    /// hitting the database with an empty query.
    ///
    /// Every successful hit returns `.confirmationRequired`, never `.success` — voice recognition
    /// is fuzzy enough that even an exact-string match deserves a verbal "did you mean…" before
    /// the call is placed.
    private func resolveContactByDisplayName(_ contact: INPerson) async -> INStartCallContactResolutionResult {

        let searchQuery: String
        if !contact.displayName.isEmpty {
            searchQuery = contact.displayName
        } else if let siriMatch = contact.siriMatches?.first, !siriMatch.displayName.isEmpty {
            searchQuery = siriMatch.displayName
            Self.logger.info("📞 displayName empty, falling back to siriMatches displayName '\(searchQuery, privacy: .private)'")
        } else {
            Self.logger.info("📞 No displayName and no siriMatches displayName, returning unsupported")
            return .unsupported(forReason: .noContactFound)
        }

        let found: [INPerson]
        do {
            found = try await PersistedObvContactIdentity.getAllReachableContactsOfNonHiddenOwnedIdentitiesAsINPerson(searchText: searchQuery)
        } catch {
            Self.logger.fault("📞 Failed to search contacts: \(error)")
            return .unsupported(forReason: .noContactFound)
        }

        switch found.count {
        case ...0:
            Self.logger.info("📞 No contacts found matching '\(searchQuery, privacy: .private)'")
            return .unsupported(forReason: .noContactFound)
        case 1:
            Self.logger.info("📞 Found exactly one contact, returning confirmationRequired")
            return .confirmationRequired(with: found.first!)
        default:
            Self.logger.info("📞 Found \(found.count) contacts, requesting disambiguation")
            return .disambiguation(with: found)
        }
    }
    
}
