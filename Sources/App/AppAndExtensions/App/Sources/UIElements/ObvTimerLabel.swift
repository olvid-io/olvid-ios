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

final class ObvTimerLabel: UILabel {
    
    private let durationFormatter: DurationFormatter = {
        let df = DurationFormatter()
        df.maximumUnitCount = 2
        return df
    }()
    private var timer: Timer? = nil
    
    func schedule(expDate: Date) {
        guard self.timer == nil else { return } // Timer already sets
        DispatchQueue.main.async {
            self.timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { (timer) in
                let delta: TimeInterval = expDate.timeIntervalSince(Date())
                var label: String? = nil
                if delta <= 0 {
                    timer.invalidate()
                } else {
                    label = self.durationFormatter.string(from: delta)
                }
                DispatchQueue.main.async {
                    self.text = label
                }
            }
            RunLoop.current.add(self.timer!, forMode: .common)
        }
    }
    
    func schedule(from: Date) {
        guard self.timer == nil else { return } // Timer already sets
        DispatchQueue.main.async {
            self.timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { (timer) in
                let delta: TimeInterval = Date().timeIntervalSince(from)
                let label = self.durationFormatter.string(from: delta)
                DispatchQueue.main.async {
                    self.text = label
                }
            }
            RunLoop.current.add(self.timer!, forMode: .common)
        }
    }
    
    func invalidate() {
        self.timer?.invalidate()
        self.timer = nil
    }
    
}
