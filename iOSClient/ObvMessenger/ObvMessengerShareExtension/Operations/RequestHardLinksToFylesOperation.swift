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
import ObvUICoreData


protocol FyleJoinsProvider: Operation {
    var fyleJoins: [FyleJoin]? { get }
}

final class RequestHardLinksToFylesOperation: Operation {

    let hardLinksToFylesManager: HardLinksToFylesManager
    let fyleJoinsProvider: FyleJoinsProvider

    private(set) var hardlinks: [HardLinkToFyle?]?

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
        let fyleElements: [FyleElement] = fyleJoins.compactMap {
            $0.genericFyleElement
        }
        hardLinksToFylesManager.requestAllHardLinksToFyles(fyleElements: fyleElements) { [weak self] hardlinks in
            guard let _self = self else { return }
            _self.hardlinks = hardlinks
            _self._isFinished = true
        }
    }

}
