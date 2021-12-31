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
import OlvidUtils


/// This singleton manages the freeze and unfreeze of all the `NewComposeMessageView` instances within the app.
///
/// Each and every `NewComposeMessageView` instance needs to register to this singleton, that keeps weak references to all these views.
/// When `NewComposeMessageView` needs to freeze (e.g., because the user tapped the send button or because the user is adding an attachment),
/// it does not freeze itself, but call this singleton instead. This singleton eventually calls the `freeze` method of the calling view, as well as the `freeze`
/// method of all the other `NewComposeMessageView` instances for the same draft. Indeed, there might be other instances under iPad for example,
/// where multiple view controllers could be showing the same discussion and thus the same draft.
///
/// When the `NewComposeMessageView` instance receives the appropriate callback or notification allowing it to unfreeze itself, it does not do so directely,
/// but call this singleton. Again, this singleton knows about all the `NewComposeMessageView` that need to be unfreezed and call the `unfreeze` method
/// on them.
///
/// This mechanism make it possible to perform a long task that freezes the composition view without any issue, even if the user decides to leave and enter back
/// into the discussion before the tasks ends. In that case, the new `NewComposeMessageView` instance will know it should start in a freezed state.
///
/// Note that the `NewComposeMessageView` instance that call this singleton to freeze itself might be deallocated by the time it can unfreeze. This is the reason why
/// this instance should never listen to notifications allowing it to unfreeze itself. Instead, it is up to this singleton to listen to these notifications.
/// 
/// In other circumstances (like attaching a picture to the draft), a callback mechanism allows the `NewComposeMessageView` instance to pass a block that will eventually
/// be executed after the attachment task is done. It should be noted that this block does *not* rely on the `NewComposeMessageView` instance to unfreeze it. Instead,
/// it call this singleton directely. This way, we know for sure that that even if the `NewComposeMessageView` instance is deallocated (e.g., because the user left
/// the discussion), this singleton will be notified that it should unfreeze, and the next time the user enters the discussion, she will indeed get an unfreezed composition view.
@available(iOS 15, *)
final class CompositionViewFreezeManager {
    
    static let shared = CompositionViewFreezeManager()

    private var currentFreezeIds = [TypeSafeManagedObjectID<PersistedDraft>: (freezeId: UUID?, progress: Progress?, views: [Weak<NewComposeMessageView>])]()
    private let internalQueue = DispatchQueue(label: "CompositionViewFreezeCoordinator internal queue")
    
    private func makeError(message: String) -> Error { NSError(domain: "CompositionViewFreezeCoordinator", code: 0, userInfo: [NSLocalizedFailureReasonErrorKey: message]) }
    
    private var notificationTokens = [NSObjectProtocol]()

    private init() {
        observeNotifications()
    }
    
    
    /// Called by all `NewComposeMessageView` at init
    func register(_ composeView: NewComposeMessageView) -> (freezeId: UUID?, progress: Progress?) {

        let draftObjectID = composeView.draft.typedObjectID

        var freezeId: UUID? = nil
        var progress: Progress? = nil
        var views = [Weak<NewComposeMessageView>]()
        
        internalQueue.sync {
            cleanCurrentFreezeIds(for: draftObjectID)

            if let existingValues = currentFreezeIds.removeValue(forKey: draftObjectID) {
                freezeId = existingValues.freezeId
                progress = existingValues.progress
                views = existingValues.views
            }

            views.append(Weak(composeView))
            currentFreezeIds[draftObjectID] = (freezeId, progress, views)
        }
        
        return (freezeId, progress)
    }
    
    
    /// Remove the references to `NewComposeMessageView` that were deallocated. Must be called on the internal queue
    private func cleanCurrentFreezeIds(for draftObjectID: TypeSafeManagedObjectID<PersistedDraft>) {
        if let existingValues = currentFreezeIds.removeValue(forKey: draftObjectID) {
            var views = existingValues.views
            views.removeAll(where: { $0.value == nil })
            if !views.isEmpty || existingValues.freezeId != nil {
                currentFreezeIds[draftObjectID] = (existingValues.freezeId, existingValues.progress, views)
            }
        }
    }
    
    
    /// Called by a `NewComposeMessageView` when it shall freeze
    func freeze(_ composeView: NewComposeMessageView) throws {
        let draftObjectID = composeView.draft.typedObjectID
        internalQueue.sync {
            cleanCurrentFreezeIds(for: draftObjectID)
            guard let existingValues = currentFreezeIds.removeValue(forKey: draftObjectID) else {
                assertionFailure()
                return
            }
            let views = existingValues.views
            assert(views.contains(where: { $0.value == composeView }))
            assert(existingValues.freezeId == nil)
            let newFreezeId = UUID()
            currentFreezeIds[draftObjectID] = (newFreezeId, nil, views)
            DispatchQueue.main.async {
                for view in views {
                    view.value?.freeze(withFreezeId: newFreezeId)
                }
            }
        }
    }
    
    
    /// Returns `true` iff the compose view is registered. Must be called on the internal queue.
    private func hasRegistered(_ composeView: NewComposeMessageView, for draftObjectID: TypeSafeManagedObjectID<PersistedDraft>) -> Bool {
        guard let values = currentFreezeIds[draftObjectID] else { return false }
        return values.views.contains(where: { $0.value == composeView })
    }
    
    
    
    /// Called to unfreeze all `NewComposeMessageView` instances corresponding to the draft objectID
    func unfreeze(_ draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, success: Bool, completion: (() -> Void)? = nil) throws {

        let (freezeIdForViewsToUnfreeze, viewsToUnfreeze) = updateCurrentFreezeIdsOnUnfreeze(draftObjectID)
        
        if let freezeIdForViewsToUnfreeze = freezeIdForViewsToUnfreeze {
            DispatchQueue.main.async {
                for view in viewsToUnfreeze {
                    view.value?.unfreeze(withFreezeId: freezeIdForViewsToUnfreeze, success: success)
                }
                completion?()
            }
        }
    }

    
    private func updateCurrentFreezeIdsOnUnfreeze(_ draftObjectID: TypeSafeManagedObjectID<PersistedDraft>) -> (freezeIdForViewsToUnfreeze: UUID?, viewsToUnfreeze: [Weak<NewComposeMessageView>]) {

        var viewsToUnfreeze = [Weak<NewComposeMessageView>]()
        var freezeIdForViewsToUnfreeze: UUID?

        internalQueue.sync {
            cleanCurrentFreezeIds(for: draftObjectID)
            guard let existingValues = currentFreezeIds.removeValue(forKey: draftObjectID),
                  let freezeId = existingValues.freezeId else {
                return
            }
            let views = existingValues.views
            currentFreezeIds[draftObjectID] = (nil, nil, views)
            viewsToUnfreeze = views
            freezeIdForViewsToUnfreeze = freezeId
        }
        
        return (freezeIdForViewsToUnfreeze, viewsToUnfreeze)
    }
        
}


// MARK: - Unfreezing views when receiving appropriate notifications

@available(iOS 15, *)
extension CompositionViewFreezeManager {
    
    private func observeNotifications() {
        notificationTokens.append(contentsOf: [
            ObvMessengerInternalNotification.observeDraftToSendWasReset { [weak self] _, draftObjectID in
                self?.processDraftToSendWasReset(draftObjectID: draftObjectID)
            },
            NewSingleDiscussionNotification.observeDraftCouldNotBeSent { [weak self] in
                self?.processDraftCouldNotBeSent(draftObjectID: $0)
            }
        ])
    }
    
    
    private func processDraftToSendWasReset(draftObjectID: TypeSafeManagedObjectID<PersistedDraft>) {

        let (freezeIdForViewsToUnfreeze, viewsToUnfreeze) = updateCurrentFreezeIdsOnUnfreeze(draftObjectID)
        
        if let freezeIdForViewsToUnfreeze = freezeIdForViewsToUnfreeze {
            DispatchQueue.main.async {
                for view in viewsToUnfreeze {
                    view.value?.unfreezeAfterDraftToSendWasReset(draftObjectID, freezeId: freezeIdForViewsToUnfreeze)
                }
            }
        }
        
    }
 
    
    private func processDraftCouldNotBeSent(draftObjectID: TypeSafeManagedObjectID<PersistedDraft>) {

        let (freezeIdForViewsToUnfreeze, viewsToUnfreeze) = updateCurrentFreezeIdsOnUnfreeze(draftObjectID)

        if let freezeIdForViewsToUnfreeze = freezeIdForViewsToUnfreeze {
            DispatchQueue.main.async {
                for view in viewsToUnfreeze {
                    view.value?.unfreezeAfterDraftCouldNotBeSent(draftObjectID, freezeId: freezeIdForViewsToUnfreeze)
                }
            }
        }

    }

}


// MARK: - Managing progresses

@available(iOS 15, *)
extension CompositionViewFreezeManager {
    
    func newProgressToAddForTrackingFreeze(draftObjectID: TypeSafeManagedObjectID<PersistedDraft>, progress: Progress) {
        
        var viewsToInform = [Weak<NewComposeMessageView>]()
        var freezeIdForViews: UUID?
        var progressToMakeAvailable: Progress?

        internalQueue.sync {
            cleanCurrentFreezeIds(for: draftObjectID)
            guard let existingValues = currentFreezeIds.removeValue(forKey: draftObjectID),
                  let freezeId = existingValues.freezeId else {
                return
            }
            let views = existingValues.views
            if let previousProgress = existingValues.progress {
                let overallProgress = Progress(totalUnitCount: previousProgress.totalUnitCount + progress.totalUnitCount)
                overallProgress.addChild(previousProgress, withPendingUnitCount: previousProgress.totalUnitCount - previousProgress.completedUnitCount)
                overallProgress.addChild(progress, withPendingUnitCount: progress.totalUnitCount - progress.completedUnitCount)
                currentFreezeIds[draftObjectID] = (freezeId, overallProgress, views)
                progressToMakeAvailable = overallProgress
            } else {
                currentFreezeIds[draftObjectID] = (freezeId, progress, views)
                progressToMakeAvailable = progress
            }
            viewsToInform = views
            freezeIdForViews = freezeId
        }
        
        if let freezeIdForViews = freezeIdForViews, let progressToMakeAvailable = progressToMakeAvailable {
            DispatchQueue.main.async {
                for view in viewsToInform {
                    view.value?.newFreezeProgressAvailable(draftObjectID, freezeId: freezeIdForViews, progress: progressToMakeAvailable)
                }
            }
        }

    }


}
