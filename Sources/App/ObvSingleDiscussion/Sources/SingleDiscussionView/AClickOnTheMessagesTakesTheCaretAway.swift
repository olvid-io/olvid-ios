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

import SwiftUI
import SwiftUIIntrospect
import UIKit


/// **A click on the messages says the reader has finished typing**, and the screen reports it so that the app can take the caret out of the composition bar.
///
/// **Catalyst only.** On a phone the keyboard already goes with a swipe on the transcript, and taking the caret away on a tap would add a second way for the
/// same thing to happen; on a Mac there is no keyboard to put away, so the swipe means nothing there and a click is the natural way to say *done here*.
/// Elsewhere this modifier attaches nothing.
///
/// **A `UITapGestureRecognizer` on the `List`'s own collection view, and not a SwiftUI gesture on the `List`**, for the reason the drop and the delayed touches
/// use the same attachment point: a SwiftUI gesture laid over a `List` is in competition with everything the rows do, where a recogniser that **does not
/// cancel touches in its view** and **recognises alongside every other recogniser** changes nothing about who wins. A click on a message still opens it,
/// selects it or shows its menu exactly as before, and the caret goes as well, which is what a click anywhere outside the bar should mean. It is a report
/// of the click and nothing more; what is done with it is the app's, see `SingleDiscussionViewActions.userClickedOnTheMessages(discussionIdentifier:)`.
///
/// **Installed once per collection view and re-checked on every introspection**, the rule this screen learnt for `dropDelegate` and `delaysContentTouches`:
/// the view belongs to SwiftUI, which may rebuild it, and the recogniser is added again only when it is not already on the view it is handed.
struct AClickOnTheMessagesTakesTheCaretAway: ViewModifier {

    /// What a click does. Called on the main actor, once per click, after the click has been delivered to whatever it landed on.
    let whatAClickDoes: () -> Void

    /// Held in `@State` so that one recogniser lives as long as this view's identity, however often the body is evaluated.
    @State private var theRecogniser = TheClickRecogniser()

    func body(content: Content) -> some View {
        #if targetEnvironment(macCatalyst)
        content
            // The same attachment point and the same version list as the drop and the delayed touches, and the same note applies: it follows the versions the
            // *screen* runs on rather than the ones this needs, so a version missing from it costs no error and simply never attaches anything.
            .introspect(.list, on: .iOS(.v18, .v26, .v27)) { collectionView in
                theRecogniser.whatAClickDoes = whatAClickDoes
                theRecogniser.installsItself(on: collectionView)
            }
        #else
        content
        #endif
    }

}


/// The recogniser behind ``AClickOnTheMessagesTakesTheCaretAway``, and the delegate that lets it recognise beside everything else.
@MainActor
private final class TheClickRecogniser: NSObject, UIGestureRecognizerDelegate {

    var whatAClickDoes: () -> Void = {}

    private lazy var recogniser: UITapGestureRecognizer = {
        let recogniser = UITapGestureRecognizer(target: self, action: #selector(theReaderClicked))
        // The click is delivered to whatever it landed on as if this recogniser were not there: nothing is cancelled and nothing is held back.
        recogniser.cancelsTouchesInView = false
        recogniser.delaysTouchesEnded = false
        recogniser.delegate = self
        return recogniser
    }()

    func installsItself(on collectionView: UICollectionView) {
        guard recogniser.view !== collectionView else { return }
        collectionView.addGestureRecognizer(recogniser)
    }

    @objc private func theReaderClicked() {
        whatAClickDoes()
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }

}


extension View {

    /// On a Mac, a click on the messages reports that the reader has finished typing — see ``AClickOnTheMessagesTakesTheCaretAway``.
    func aClickOnTheMessagesTakesTheCaretAway(_ whatAClickDoes: @escaping () -> Void) -> some View {
        modifier(AClickOnTheMessagesTakesTheCaretAway(whatAClickDoes: whatAClickDoes))
    }

}
