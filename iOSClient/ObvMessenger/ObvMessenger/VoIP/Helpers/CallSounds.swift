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
import UIKit
import AVFoundation
import ObvUICoreData


enum CallSound: Sound, CaseIterable {

    case ringing
    case connect
    case disconnect

    var filename: String? {
        switch self {
        case .ringing: return "ringing.mp3"
        case .connect: return "connect.mp3"
        case .disconnect: return "disconnect.mp3"
        }
    }

    var loops: Bool {
        switch self {
        case .ringing:
            return true
        case .connect, .disconnect:
            return false
        }
    }

    var feedback: UINotificationFeedbackGenerator.FeedbackType? {
        switch self {
        case .ringing:
            return nil
        case .connect:
            return .success
        case .disconnect:
            return .error
        }
    }
}

@MainActor
final class CallSounds {
    static private(set) var shared = SoundsPlayer<CallSound>()
}
