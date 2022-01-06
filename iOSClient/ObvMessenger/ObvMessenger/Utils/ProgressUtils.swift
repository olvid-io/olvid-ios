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

class Progresses: Progress {

    private var pausedKvo: [Progress: NSKeyValueObservation] = [:]
    private var canceledKvo: [Progress: NSKeyValueObservation] = [:]
    private var fractionCompletedKvo: [Progress: NSKeyValueObservation] = [:]

    private var completedUnitCounts: [Progress: Int64] = [:]

    var children: [Progress] = []

    private let queue = DispatchQueue(label: "SynchronizedArrayAccess", attributes: .concurrent)

    override var isPausable: Bool {
        get { self.children.allSatisfy { p in p.isPausable }}
        set { self.children.forEach { p in p.isPausable = newValue }}
    }

    private func update() {
        if children.contains(where: { c in c.isPaused }) {
            self.pause()
        } else {
            self.resume()
        }
        if children.contains(where: { c in c.isCancelled }) {
            self.cancel()
        }
    }

    convenience init(of children: [Progress]) {
        self.init(parent: nil, userInfo: nil)
        self.children = children
        queue.sync {
            self.children.forEach { p in
                self.totalUnitCount += p.totalUnitCount
                self.completedUnitCount += p.completedUnitCount
                completedUnitCounts[p] = p.completedUnitCount
            }
        }
        self.children.forEach { p in
            pausedKvo[p] = p.observe(\.isPaused) { [weak self] (progress, _) in
                self?.update()
            }
            canceledKvo[p] = p.observe(\.isCancelled) { [weak self] (progress, _) in
                self?.update()
            }
            fractionCompletedKvo[p] = p.observe(\.fractionCompleted) { [weak self] (progress, change) in
                guard let self_ = self else { return }
                self_.queue.sync {
                    let previous = self_.completedUnitCounts[progress]!
                    let new = p.completedUnitCount
                    self_.completedUnitCount += new - previous
                    self_.completedUnitCounts[progress] = new
                }
            }
        }
        update()
    }
}
