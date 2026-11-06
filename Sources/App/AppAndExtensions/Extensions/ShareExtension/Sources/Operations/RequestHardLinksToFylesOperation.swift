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
import ObvUICoreData



final class RequestHardLinksToFylesOperation: Operation, @unchecked Sendable {

    let hardLinksToFylesManager: HardLinksToFylesManager
    let fyleJoinsProvider: FyleJoinsProvider

    private(set) var hardlinks: [HardLinkToFyle?]?

    /// Same hardlinks as `hardlinks`, but each paired with the `index` of the `FyleJoin` it originates from.
    /// Required because mapping `fyleJoins` to their `genericFyleElement` drops any join with a nil element,
    /// which would otherwise make a positional re-enumeration diverge from `FyleJoin.index` — the value used
    /// later for selection and transcoding.
    private(set) var indexedHardlinks: [(index: Int, hardlink: HardLinkToFyle?)]?

    init(hardLinksToFylesManager: HardLinksToFylesManager, fyleJoinsProvider: FyleJoinsProvider) {
        self.hardLinksToFylesManager = hardLinksToFylesManager
        self.fyleJoinsProvider = fyleJoinsProvider
        super.init()
    }

    private var _isFinished = false {
        willSet { willChangeValue(for: \.isFinished) }
        didSet { didChangeValue(for: \.isFinished) }
    }
    override var isFinished: Bool { _isFinished }

    override func main() {
        assert(fyleJoinsProvider.isFinished)
        guard let fyleJoins = fyleJoinsProvider.fyleJoins else {
            assertionFailure()
            _isFinished = true
            return
        }
        // Keep track of the originating FyleJoin index for each FyleElement, so the resulting hardlinks can
        // be matched back to the correct FyleJoin even though joins with a nil genericFyleElement are dropped.
        let indexedFyleElements: [(index: Int, fyleElement: FyleElement)] = fyleJoins.compactMap { fyleJoin in
            guard let fyleElement = fyleJoin.genericFyleElement else { return nil }
            return (fyleJoin.index, fyleElement)
        }
        let fyleElements: [FyleElement] = indexedFyleElements.map { $0.fyleElement }
        hardLinksToFylesManager.requestAllHardLinksToFyles(fyleElements: fyleElements) { [weak self] hardlinks in
            guard let _self = self else { return }
            _self.hardlinks = hardlinks
            // `requestAllHardLinksToFyles` returns hardlinks positionally aligned with `fyleElements`, so we
            // can zip them back with the originating FyleJoin indices captured above.
            _self.indexedHardlinks = zip(indexedFyleElements, hardlinks).map { (index: $0.0.index, hardlink: $0.1) }
            _self._isFinished = true
        }
    }

}
