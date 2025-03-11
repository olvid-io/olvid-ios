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
import Combine
import ObvUICoreData


protocol ScreenCaptureDetectorDelegate: AnyObject {
    func screenCaptureOfSensitiveMessagesWasDetected(discussionPermanentID: DiscussionPermanentID) async
    func screenshotOfSensitiveMessagesWasDetected(discussionPermanentID: DiscussionPermanentID) async
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
    private let persistedDiscussionPermanentIDsOfShownDiscussion: AnyPublisher<DiscussionPermanentID?, Never> = OlvidUserActivitySingleton.shared.$currentDiscussionPermanentID
        .eraseToAnyPublisher()
    
    
    // MARK: - Tracking the currently displayed messages with limited visibility

    /// Publishers tracking notifications sent by the discussion view controller, storing the discussion object ID and the set of objectIDs of displayed messages with limited visibility.
    /// The discussion objectID might be distinct from the `persistedDiscussionObjectIDOfShownDiscussion` above, but only for a brief moment.
    ///
    /// Distinguishing the discussion objectID from the `ObvUserActivitySingleton` from the one sent within the `UpdatedSetOfCurrentlyDisplayedMessagesWithLimitedVisibility` notification allows to make sure the user activity is indeed the one we expect when receiving the notification. Note that we reset this publisher as soon as the user leaves the discussion.
    @Published var currentlyDisplayedMessagesWithLimitedVisibility: (discussionPermanentID: DiscussionPermanentID, messagePermanentIDs: Set<ObvManagedObjectPermanentID<PersistedMessage>>)?
    private var cancellableForObservingWhenTheUserLeavesTheDiscussion: AnyCancellable?
    
    private func startUpdatingCurrentlyDisplayedMessagesWithLimitedVisibility() {
        cancellableForObservingWhenTheUserLeavesTheDiscussion = persistedDiscussionPermanentIDsOfShownDiscussion
            .receive(on: RunLoop.main)
            .sink { [weak self] discussionPermanentID in
            if discussionPermanentID == nil {
                // The user left the discussion
                self?.currentlyDisplayedMessagesWithLimitedVisibility = nil
            }
        }
    }
    
    
    @MainActor
    func processUpdatedSetOfCurrentlyDisplayedMessagesWithLimitedVisibility(discussionPermanentID: ObvManagedObjectPermanentID<PersistedDiscussion>, messagePermanentIDs: Set<ObvManagedObjectPermanentID<PersistedMessage>>) {
        currentlyDisplayedMessagesWithLimitedVisibility = (discussionPermanentID, messagePermanentIDs)
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
        cancellableForScreenShotDetection = persistedDiscussionPermanentIDsOfShownDiscussion
            .combineLatest($screenShotTaken, $currentlyDisplayedMessagesWithLimitedVisibility)
            .sink { [weak self] activeDiscussionPermanentID, screenShotTaken, discussionAndMessagePermanentIDs in
                
                // Make sure there is an active discussion, a non-nil displayed discussion/messages with limited visibility, and that a screenshot was taken
                guard let activeDiscussionPermanentID, let discussionAndMessagePermanentIDs, screenShotTaken else { return }

                // Make sure that the active discussion corresponds to the one that sent us the set of displayed messages with limited visibility
                guard activeDiscussionPermanentID == discussionAndMessagePermanentIDs.discussionPermanentID else { return }

                // Make sure the set of displayed messages is not empty
                guard !discussionAndMessagePermanentIDs.messagePermanentIDs.isEmpty else { return }

                // If we reach this point, we detected a screenshot
                Task {
                    await self?.delegate?.screenshotOfSensitiveMessagesWasDetected(discussionPermanentID: activeDiscussionPermanentID)
                }
                
            }
    }
    
    
    // MARK: - Detecting screen captures (e.g., recordings)
    
    private let mainScreenIsCaptured = UIScreen.main.publisher(for: \.isCaptured)
    private var cancellableForMainScreenIsCaptured: AnyCancellable?

    private var permanentIDsOfDiscussionsForWhichScreenCaptureWasDetected = Set<DiscussionPermanentID>()

    private func startDetectingScreenCaptures() {
        cancellableForMainScreenIsCaptured = persistedDiscussionPermanentIDsOfShownDiscussion
            .combineLatest(mainScreenIsCaptured, $currentlyDisplayedMessagesWithLimitedVisibility)
            .sink { [weak self] activeDiscussionPermanentID, mainScreenIsCaptured, discussionAndMessagePermanentIDs in

                // Make sure there is an active discussion, a non-nil displayed discussion/messages with limited visibility, and that the screen is being captured
                guard let activeDiscussionPermanentID, let discussionAndMessagePermanentIDs, mainScreenIsCaptured else { return }

                // Make sure that the active discussion corresponds to the one that sent us the set of displayed messages with limited visibility
                guard activeDiscussionPermanentID == discussionAndMessagePermanentIDs.discussionPermanentID else { return }

                // Make sure the set of displayed messages is not empty
                guard !discussionAndMessagePermanentIDs.messagePermanentIDs.isEmpty else { return }

                // We don't want to detect a screen capture for the same discussion twice
                guard self?.permanentIDsOfDiscussionsForWhichScreenCaptureWasDetected.contains(activeDiscussionPermanentID) == false else { return }
                self?.permanentIDsOfDiscussionsForWhichScreenCaptureWasDetected.insert(activeDiscussionPermanentID)

                // If we reach this point, we detected a screen capture
                Task {
                    await self?.delegate?.screenCaptureOfSensitiveMessagesWasDetected(discussionPermanentID: activeDiscussionPermanentID)
                }
                
            }
    }
    
}
