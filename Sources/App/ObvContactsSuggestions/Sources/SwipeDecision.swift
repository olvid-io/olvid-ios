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

import CoreGraphics


/// What a drag on the top card amounts to, kept apart from the view so that it can be tested.
enum SwipeDecision: Equatable {

    case accept
    case decline
    case cancel

    /// The fraction of the card's width a drag must cover to count, when it is released slowly.
    static let distanceThreshold: CGFloat = 0.35
    /// A flick counts when the drag would have covered this fraction of the width had it been left to run on.
    static let predictedDistanceThreshold: CGFloat = 0.8

    /// - Parameters:
    ///   - translation: How far the finger moved horizontally, positive to the right.
    ///   - predictedEndTranslation: Where the gesture predicts the finger would have stopped.
    ///   - cardWidth: The width of the card.
    static func decide(translation: CGFloat, predictedEndTranslation: CGFloat, cardWidth: CGFloat) -> SwipeDecision {
        guard cardWidth > 0 else { return .cancel }
        let distance = translation / cardWidth
        let predictedDistance = predictedEndTranslation / cardWidth
        // A flick back towards the centre cancels even if the card has gone far enough.
        if distance >= distanceThreshold && predictedDistance >= distanceThreshold {
            return .accept
        }
        if distance <= -distanceThreshold && predictedDistance <= -distanceThreshold {
            return .decline
        }
        if predictedDistance >= predictedDistanceThreshold && translation > 0 {
            return .accept
        }
        if predictedDistance <= -predictedDistanceThreshold && translation < 0 {
            return .decline
        }
        return .cancel
    }


    /// How strongly the green or red fill covers the card, from 0 to 1, for a translation.
    static func progress(translation: CGFloat, cardWidth: CGFloat) -> CGFloat {
        guard cardWidth > 0 else { return 0 }
        return min(1, abs(translation) / (cardWidth * distanceThreshold))
    }


    /// Whether a drag has reached the line past which letting it go slowly decides, to the left or to the right. The green or red fill is full there.
    static func isPastTheDecisionLine(translation: CGFloat, cardWidth: CGFloat) -> Bool {
        progress(translation: translation, cardWidth: cardWidth) >= 1
    }

}
