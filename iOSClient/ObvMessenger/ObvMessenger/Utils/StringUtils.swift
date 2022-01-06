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


extension String {
    
    func extractURLs() -> [URL] {
        guard let urlDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return [] }
        let range = NSRange(location: 0, length: self.utf16.count)
        let matches = urlDetector.matches(in: self, options: [], range: range)
        let urls: [URL] = matches.compactMap { (match) -> URL? in
            guard let rangeOfMatch = Range(match.range, in: self) else { return nil }
            return URL(string: String(self[rangeOfMatch]))
        }
        return urls
    }

    func trimmingWhitespacesAndNewlines() -> String {
        return trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }

    func trimmingWhitespacesAndNewlinesAndMapToNilIfZeroLength() -> String? {
        return trimmingWhitespacesAndNewlines().mapToNilIfZeroLength()
    }

    func mapToNilIfZeroLength() -> String? {
        return self.isEmpty ? nil : self
    }

}
