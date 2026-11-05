/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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


/// Decides whether a move into, out of, or between discussions slides. This is the only place that decides it.
///
/// On a Mac, it does not slide. The discussion is a column of a window there, not a screen the reader walks into: the list stays where it is and only the
/// right-hand side is replaced. Everywhere else the discussion really is pushed on top of the list, and the slide is what says so.
///
/// Passing `animated: false` is not enough. The back button of the navigation bar belongs to UIKit and never asks us how to animate, which is why this type
/// is also a `UINavigationControllerDelegate`: an animation controller of no duration is how a navigation controller is told that a move it makes on its own
/// must not slide. Both mechanisms read `isAnimated`.
///
/// The test is whether either side of the move is a `SomeSingleDiscussionViewController`, not which navigation controller is asking. The details column of
/// the split view holds nothing but the placeholder and discussions, but the flow controllers of a collapsed window also hold contacts, groups and settings,
/// which keep their slide.
///
/// Two consequences worth knowing. The appear and disappear of two discussions now happen in the same turn of the run loop, and UIKit may order them either
/// way, so whatever tracks the current discussion must tolerate both orders. And the transition no longer covers the loading of the discussion: the reader
/// sees the spinner of `NewSingleDiscussionViewController` instead of the outgoing discussion.
///
/// The interactive pop is refused on a Mac, in `ObvFlowController.theInteractivePopMayBegin()`. A stack that does not look like a stack has no swipe back.
@MainActor
final class TheTransitionBetweenDiscussions: NSObject, UINavigationControllerDelegate {

    /// `false` on a Mac, `true` everywhere else.
    static var isAnimated: Bool {
        #if targetEnvironment(macCatalyst)
        return false
        #else
        return true
        #endif
    }


    func navigationController(_ navigationController: UINavigationController, animationControllerFor operation: UINavigationController.Operation, from fromVC: UIViewController, to toVC: UIViewController) -> (any UIViewControllerAnimatedTransitioning)? {
        guard !Self.isAnimated else { return nil }
        let movesIntoOrOutOfADiscussion = (fromVC is any SomeSingleDiscussionViewController) || (toVC is any SomeSingleDiscussionViewController)
        guard movesIntoOrOutOfADiscussion else { return nil }
        return TheSwapThatTakesNoTime()
    }

}


/// Puts the arriving screen in place and completes the transition, within the same call.
///
/// A duration of zero is not a very short animation: nothing is added to the animation curves at all, so no frame shows both screens at once. The frame
/// comes from `finalFrame(for:)` rather than from the container's bounds, which keeps it correct when the window is resized, and when one screen shows a bar
/// and the other does not.
///
/// `view(forKey: .to)` returns nil when the arriving view is not ours to manage. Completing without adding a view would leave the navigation controller with
/// a correct stack and an empty column, and nothing would push the discussion again, so we fall back to the view controller's own `view`. It is the same
/// view in every case that concerns us.
private final class TheSwapThatTakesNoTime: NSObject, UIViewControllerAnimatedTransitioning {

    func transitionDuration(using transitionContext: (any UIViewControllerContextTransitioning)?) -> TimeInterval {
        return 0
    }


    func animateTransition(using transitionContext: any UIViewControllerContextTransitioning) {
        guard let toViewController = transitionContext.viewController(forKey: .to) else {
            // Nothing to put in place. We must still complete: a transition that never completes leaves the navigation controller unusable.
            assertionFailure()
            transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
            return
        }
        let viewProvidedByTheContext = transitionContext.view(forKey: .to)
        if viewProvidedByTheContext == nil {
            // The fallback is the same view in every case that concerns us. This is how we find out that it is not.
            assertionFailure()
        }
        let toView = viewProvidedByTheContext ?? toViewController.view
        toView?.frame = transitionContext.finalFrame(for: toViewController)
        if let toView {
            transitionContext.containerView.addSubview(toView)
        }
        transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
    }

}
