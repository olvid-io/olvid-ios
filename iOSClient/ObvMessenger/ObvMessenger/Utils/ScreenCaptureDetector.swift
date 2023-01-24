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
  

import UIKit
import Combine


protocol ScreenCaptureDetectorDelegate: AnyObject {
    func screenCaptureOfSensitiveMessagesWasDetected(persistedDiscussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>) async
    func screenshotOfSensitiveMessagesWasDetected(persistedDiscussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>) async
}



@MainActor
final class ScreenCaptureDetector {
    
    private weak var delegate: ScreenCaptureDetectorDelegate?

    func setDelegate(to newDelegate: ScreenCaptureDetectorDelegate?) {
        self.delegate = newDelegate
    }
    
    func startDetecting() {
        startDetectingScreenshots()
        startDetectingScreenCaptures()
        startUpdatingCurrentlyDisplayedMessagesWithLimitedVisibility()
    }

    /// Publisher only set when the user is within a discussion
    private let persistedDiscussionObjectIDOfShownDiscussion: AnyPublisher<TypeSafeManagedObjectID<PersistedDiscussion>?, Never> = ObvUserActivitySingleton.shared.$currentUserActivity
        .map { currentUserActivity in
            switch currentUserActivity {
            case .continueDiscussion(persistedDiscussionObjectID: let persistedDiscussionObjectID):
                return persistedDiscussionObjectID
            default:
                return nil
            }
        }
        .eraseToAnyPublisher()
    
    
    // MARK: - Tracking the currently displayed messages with limited visibility

    /// Publishers tracking notifications sent by the discussion view controller, storing the discussion object ID and the set of objectIDs of displayed messages with limited visibility.
    /// The discussion objectID might be distinct from the `persistedDiscussionObjectIDOfShownDiscussion` above, but only for a brief moment.
    ///
    /// Distinguishing the discussion objectID from the `ObvUserActivitySingleton` from the one sent within the `UpdatedSetOfCurrentlyDisplayedMessagesWithLimitedVisibility` notification allows to make sure the user activity is indeed the one we expect when receiving the notification. Note that we reset this publisher as soon as the user leaves the discussion.
    @Published var currentlyDisplayedMessagesWithLimitedVisibility: (discussionObjectID: TypeSafeManagedObjectID<PersistedDiscussion>, messageObjectIDs: Set<TypeSafeManagedObjectID<PersistedMessage>>)?
    private var token: NSObjectProtocol?
    private var cancellableForObservingWhenTheUserLeavesTheDiscussion: AnyCancellable?
    
    private func startUpdatingCurrentlyDisplayedMessagesWithLimitedVisibility() {
        token = NewSingleDiscussionNotification.observeUpdatedSetOfCurrentlyDisplayedMessagesWithLimitedVisibility { [weak self] discussionObjectID, messageObjectIDs in
            self?.currentlyDisplayedMessagesWithLimitedVisibility = (discussionObjectID, messageObjectIDs)
        }
        cancellableForObservingWhenTheUserLeavesTheDiscussion = persistedDiscussionObjectIDOfShownDiscussion.sink { [weak self] discussionObjectID in
            if discussionObjectID == nil {
                // The user left the discussion
                self?.currentlyDisplayedMessagesWithLimitedVisibility = nil
            }
        }
    }
    
    
    // MARK: - Detecting screenshots
    
    /// Switches to `true` when a screenshot is taken, then back to `false`.
    @Published var screenShotTaken: Bool = false
    private var cancellableForUpdatingScreenShotTaken: AnyCancellable?
    private var cancellableForScreenShotDetection: AnyCancellable?

    private func startDetectingScreenshots() {
        cancellableForUpdatingScreenShotTaken = NotificationCenter.default.publisher(for: UIApplication.userDidTakeScreenshotNotification).sink { [weak self] _ in
            self?.screenShotTaken = true
            self?.screenShotTaken = false
        }
        cancellableForScreenShotDetection = persistedDiscussionObjectIDOfShownDiscussion
            .combineLatest($screenShotTaken, $currentlyDisplayedMessagesWithLimitedVisibility)
            .sink { [weak self] activeDiscussionObjectID, screenShotTaken, discussionAndMessageObjectIDs in
                
                // Make sure there is an active discussion, a non-nil displayed discussion/messages with limited visibility, and that a screenshot was taken
                guard let activeDiscussionObjectID, let discussionAndMessageObjectIDs, screenShotTaken else { return }
                
                // Make sure that the active discussion corresponds to the one that sent us the set of displayed messages with limited visibility
                guard activeDiscussionObjectID == discussionAndMessageObjectIDs.discussionObjectID else { return }
                
                // Make sure the set of displayed messages is not empty
                guard !discussionAndMessageObjectIDs.messageObjectIDs.isEmpty else { return }
                
                // If we reach this point, we detected a screenshot
                Task {
                    await self?.delegate?.screenshotOfSensitiveMessagesWasDetected(persistedDiscussionObjectID: activeDiscussionObjectID)
                }
                
            }
    }
    
    
    // MARK: - Detecting screen captures (e.g., recordings)
    
    private let mainScreenIsCaptured = UIScreen.main.publisher(for: \.isCaptured)
    private var cancellableForMainScreenIsCaptured: AnyCancellable?

    private var objectIDsOfDiscussionsForWhichScreenCaptureWasDetected = Set<TypeSafeManagedObjectID<PersistedDiscussion>>()

    private func startDetectingScreenCaptures() {
        cancellableForMainScreenIsCaptured = persistedDiscussionObjectIDOfShownDiscussion
            .combineLatest(mainScreenIsCaptured, $currentlyDisplayedMessagesWithLimitedVisibility)
            .sink { [weak self] activeDiscussionObjectID, mainScreenIsCaptured, discussionAndMessageObjectIDs in

                // Make sure there is an active discussion, a non-nil displayed discussion/messages with limited visibility, and that the screen is being captured
                guard let activeDiscussionObjectID, let discussionAndMessageObjectIDs, mainScreenIsCaptured else { return }
                
                // Make sure that the active discussion corresponds to the one that sent us the set of displayed messages with limited visibility
                guard activeDiscussionObjectID == discussionAndMessageObjectIDs.discussionObjectID else { return }
                
                // Make sure the set of displayed messages is not empty
                guard !discussionAndMessageObjectIDs.messageObjectIDs.isEmpty else { return }
                
                // We don't want to detect a screen capture for the same discussion twice
                guard self?.objectIDsOfDiscussionsForWhichScreenCaptureWasDetected.contains(activeDiscussionObjectID) == false else { return }
                self?.objectIDsOfDiscussionsForWhichScreenCaptureWasDetected.insert(activeDiscussionObjectID)

                // If we reach this point, we detected a screen capture
                Task {
                    await self?.delegate?.screenCaptureOfSensitiveMessagesWasDetected(persistedDiscussionObjectID: activeDiscussionObjectID)
                }
                
            }
    }
    
}
