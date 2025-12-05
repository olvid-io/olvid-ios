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

import UIKit
import OSLog
import ObvTypes
import ObvUICoreData
import ObvAppTypes
import Combine
import ObvAppCoreConstants


final class OlvidUserActivitySingleton: NSObject {
    
    static let shared = OlvidUserActivitySingleton()
    
    private override init() {
        super.init()
        produceStreamsOnChangeOfDiscussionID()
    }

    private let internalQueue = DispatchQueue(label: "OlvidUserActivitySingleton internal queue")
    
    private static let logger = Logger(subsystem: ObvAppCoreConstants.logSubsystem, category: "OlvidUserActivitySingleton")

    public struct DiscussionID: Equatable {
        let permanentID: DiscussionPermanentID
        let objectID: TypeSafeManagedObjectID<PersistedDiscussion>
    }
    
    @Published private(set) var currentUserActivity: OlvidUserActivity?
    @Published private(set) var currentDiscussionID: DiscussionID?
    
    /// Allows to track the current active appearance. Particularly useful under macOS, e.g., when deciding whether to show a user notification or not.
    @Published private(set) var traitCollectionActiveAppearance: UIUserInterfaceActiveAppearance?

    private var cancellables: Set<AnyCancellable> = []
    
    private var continuationForStreamUUID = [UUID: AsyncStream<OlvidUserActivitySingleton.DiscussionID?>.Continuation]()
    
}


// MARK: - Setting the UIUserInterfaceActiveAppearance

extension OlvidUserActivitySingleton {
    
    /// Called by the root view controller each time the user interface active appearance changes.
    @MainActor
    func setTraitCollectionActiveAppearance(_ traitCollectionActiveAppearance: UIUserInterfaceActiveAppearance) {
        self.traitCollectionActiveAppearance = traitCollectionActiveAppearance
    }
    
}

// MARK: - Methods allowing the MainFlowController and the ObvFlowController to update the current activity

extension OlvidUserActivitySingleton {
    
    @MainActor
    func switchCurrentOwnedCryptoId(to newOwnedCryptoId: ObvCryptoId, viewController: UIViewController) async {
                
        let newUserActivity: OlvidUserActivity

        if let currentUserActivity {
            newUserActivity = currentUserActivity
                .withUpdatedOwnedCryptoId(newOwnedCryptoId)
        } else {
            newUserActivity = .init(ownedCryptoId: newOwnedCryptoId, currentFlow: .latestDiscussions, currentDiscussion: nil)
        }
        
        // Update
        
        updateWith(newUserActivity: newUserActivity, viewController: viewController)

    }
    
    @MainActor
    func switchCurrentFlow(to newCurrentFlow: ObvAppTypes.ObvFlow, currentOwnedCryptoId: ObvCryptoId, viewController: UIViewController) {
        
        let newUserActivity: OlvidUserActivity

        if let currentUserActivity {
            newUserActivity = currentUserActivity
                .widthUpdatedCurrentFlow(newCurrentFlow)
                .withUpdatedOwnedCryptoId(currentOwnedCryptoId)
        } else {
            newUserActivity = .init(ownedCryptoId: currentOwnedCryptoId, currentFlow: newCurrentFlow, currentDiscussion: nil)
        }

        // Update
        
        updateWith(newUserActivity: newUserActivity, viewController: viewController)

    }
    
    
    @MainActor
    func switchCurrentDiscussion(to newCurrentDiscussion: ObvDiscussionIdentifier?, viewController: UIViewController) {
        
        guard let currentUserActivity else {
            Self.logger.fault("Cannot update the discussion of the current user activity as the current user activity is nil")
            assertionFailure()
            return
        }
        
        let newUserActivity: OlvidUserActivity = currentUserActivity.withUpdatedCurrentDiscussion(newCurrentDiscussion)

        // Update
        
        updateWith(newUserActivity: newUserActivity, viewController: viewController)
        
    }

    
}



// MARK: - Private methods

extension OlvidUserActivitySingleton {
    
    private func determineCurrentDiscussionWhenShowing(_ viewController: SomeSingleDiscussionViewController) -> ObvDiscussionIdentifier? {
        assert(Thread.isMainThread)
        if let persistedDiscussion = try? PersistedDiscussion.get(objectID: viewController.discussionObjectID.objectID, within: ObvStack.shared.viewContext),
           let discussionIdentifier = persistedDiscussion.discussionIdentifier {
            return discussionIdentifier
        } else {
            assertionFailure()
            return nil
        }
    }
    
    
    private func determineDiscussionPermanentID(from discussionActivityIdentifier: ObvDiscussionIdentifier) -> DiscussionID? {
        assert(Thread.isMainThread)
        let discussionId = discussionActivityIdentifier.toDiscussionIdentifier()
        if let discussion = try? PersistedDiscussion.getPersistedDiscussion(ownedCryptoId: discussionActivityIdentifier.ownedCryptoId, discussionId: discussionId, within: ObvStack.shared.viewContext) {
            return DiscussionID(permanentID: discussion.discussionPermanentID, objectID: discussion.typedObjectID)
        } else {
            assertionFailure()
            return nil
        }
    }
    
    
    private func updateWith(newUserActivity: OlvidUserActivity, viewController: UIViewController) {
        
        // Determine the current discussion's permanent ID
        
        let newCurrentDiscussionPermanentID: OlvidUserActivitySingleton.DiscussionID?
        if let currentDiscussion = newUserActivity.currentDiscussion {
            newCurrentDiscussionPermanentID = determineDiscussionPermanentID(from: currentDiscussion)
        } else {
            newCurrentDiscussionPermanentID = nil
        }

        // Check whether the owned identity associated to the new user activity corresponds to a hidden profile.
        // If this is the case, we won't publish the new user activity.
        
        let newUserActivityIsForHiddenProfile: Bool
        do {
            let ownedIdentity = try PersistedObvOwnedIdentity.get(cryptoId: newUserActivity.ownedCryptoId, within: ObvStack.shared.viewContext)
            newUserActivityIsForHiddenProfile = ownedIdentity?.isHidden ?? false
        } catch {
            assertionFailure()
            newUserActivityIsForHiddenProfile = false
        }
        
        internalQueue.async { [weak self] in
            
            guard let self else { return }
            
            let previousUserActivity = self.currentUserActivity
                                    
            guard newUserActivity != previousUserActivity else { return }
            
            let previousDiscussionID = self.currentDiscussionID
            
            self.currentUserActivity = newUserActivity
            self.currentDiscussionID = newCurrentDiscussionPermanentID
            
            debugPrint("📺 Current user activity is \(newUserActivity.debugDescription)")
            debugPrint("📺 Current discussion permanentID is \(currentDiscussionID?.objectID.debugDescription ?? "None")")

            // Inform the system about the user new activity
  
            if let newUserActivity = self.currentUserActivity, !newUserActivityIsForHiddenProfile {
                DispatchQueue.main.async {
                    viewController.userActivity = newUserActivity
                }
            }
            
            // Notify
  
            if previousDiscussionID != self.currentDiscussionID {
                ObvMessengerInternalNotification.currentDiscussionDidChange(previousDiscussion: previousDiscussionID?.permanentID, currentDiscussion: currentDiscussionID?.permanentID)
                    .postOnDispatchQueue()
            }
            
            // If the activity changed, re-enable the idle timer of the app
            
            if previousUserActivity != self.currentUserActivity {
                DispatchQueue.main.async {
                    IdleTimerManager.shared.forceEnableIdleTimer()
                }
            }

        }

    }
    
}


// MARK: - Producing a stream of OlvidUserActivitySingleton.DiscussionID

extension OlvidUserActivitySingleton {
    
    func getAsyncStreamOfOlvidUserActivitySingletonDiscussionID() -> (streamUUID: UUID, stream: AsyncStream<OlvidUserActivitySingleton.DiscussionID?>) {
        let streamUUID = UUID()
        let stream = AsyncStream(OlvidUserActivitySingleton.DiscussionID?.self) { [weak self] (continuation: AsyncStream<OlvidUserActivitySingleton.DiscussionID?>.Continuation) in
            guard let self else { continuation.finish(); return }
            continuationForStreamUUID[streamUUID] = continuation
        }
        return (streamUUID, stream)

    }
    
    func finishAsyncStreamOfOlvidUserActivitySingletonDiscussionID(streamUUID: UUID) {
        if let continuation = continuationForStreamUUID.removeValue(forKey: streamUUID) {
            continuation.finish()
        }
    }
    
    private func produceStreamsOnChangeOfDiscussionID() {
        self.$currentDiscussionID
            .sink { [weak self] newValue in
                self?.continuationForStreamUUID.values.forEach { continuation in
                    continuation.yield(newValue)
                }
            }
            .store(in: &cancellables)
    }
    
}
