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

import Foundation

public enum Note: Int, CaseIterable {
    case C = 0
    case Csharp
    case D
    case Dsharp
    case E
    case F
    case Fsharp
    case G
    case Gsharp
    case A
    case Asharp
    case B
    case C2

    var identifier: String { String(describing: self) }
    var description: String { NSLocalizedString(identifier, comment: "") }
    public var index: String { String(format: "%02d", rawValue+1) }

    public static func random() -> Note {
        let i = Int.random(in: 0..<Note.allCases.count)
        return Note(rawValue: i) ?? .C
    }


    static func generateNote(from string: String) -> Note {
        guard let data = string.data(using: .utf8) else {
            assertionFailure(); return .C
        }
        let noteRawValue = data.hashValue % allCases.count
        return Note(rawValue: noteRawValue) ?? .C
    }

}
