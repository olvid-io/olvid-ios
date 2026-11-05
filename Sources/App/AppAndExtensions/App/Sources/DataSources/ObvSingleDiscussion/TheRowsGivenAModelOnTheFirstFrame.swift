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

import Foundation


/// Which rows of a discussion are given a model before its first frame: a window of a fixed size around the row the discussion opens on.
///
/// A row without a model is drawn as a skeleton one line tall, and grows when its model arrives. On screen, that growth moves everything below it.
enum TheRowsGivenAModelOnTheFirstFrame {

    /// The `size` rows around `indexOfTheRowItOpensOn`, centred on it where the discussion allows.
    ///
    /// **Moved back inside the discussion rather than clipped at its ends**, so the window always holds `size` rows when the discussion has them. A clipped
    /// window around a marker just above the last message would keep only its upper half: 13 rows, where an entry with nothing unread gets 25. A tall window
    /// would then show skeletons above them.
    static func range(around indexOfTheRowItOpensOn: Int, amongRows numberOfRows: Int, size: Int) -> Range<Int> {
        let size = max(0, min(size, numberOfRows))
        let centred = indexOfTheRowItOpensOn - size / 2
        let start = min(max(0, centred), numberOfRows - size)
        return start..<(start + size)
    }

}
