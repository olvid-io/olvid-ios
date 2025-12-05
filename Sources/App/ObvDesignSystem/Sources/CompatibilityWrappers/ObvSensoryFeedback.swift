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

import SwiftUI


public enum ObvSensoryFeedback {
    // Indicating start and stop
    case start
    case stop
    // Indicating changes and selections
    case alignment
    case decrease
    case increase
    case levelChange
    case selection
    // Indicating the outcome of an operation
    case success
    case warning
    case error
}

struct ObvSensoryFeedbacks<T: Equatable>: ViewModifier {
    
    let obvFeedback: ObvSensoryFeedback
    let trigger: T
    
    init(_ obvFeedback: ObvSensoryFeedback, trigger: T) {
        self.obvFeedback = obvFeedback
        self.trigger = trigger
    }
    
    @available(iOS 17, *)
    var feedback: SensoryFeedback {
        switch obvFeedback {
        case .start: return .start
        case .stop: return .stop
        case .alignment: return .alignment
        case .decrease: return .decrease
        case .increase: return .increase
        case .levelChange: return .levelChange
        case .selection: return .selection
        case .success: return .success
        case .warning: return .warning
        case .error: return .error
        }
    }
    
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content
                .sensoryFeedback(feedback, trigger: trigger)
        } else {
            content
        }
    }

}


extension View {
    
    /// Wrapper around Apple's `sensoryFeedback<T>(_ feedback: SensoryFeedback, trigger: T)` API, which
    /// is onylavailable on iOS17+.
    public func sensoryFeedbackOniOS17<T>(_ feedback: ObvSensoryFeedback, trigger: T) -> some View where T : Equatable {
        self.modifier(ObvSensoryFeedbacks(feedback, trigger: trigger))
    }
    
}
