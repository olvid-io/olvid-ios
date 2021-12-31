/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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

/**
 The protocol that types may implement if they wish to be notified of significant
 operation lifecycle events.
 */
protocol OperationDelegate: AnyObject {

    /// Invoked immediately prior to the `Operation`'s `execute()` method.
    func operationWillExecute(operation: Operation)

    /// Invoked as an `Operation` finishes. An operation always finishes, either becauses it cancelled, or because eveything went ok.
    func operationDidFinish(operation: Operation)
    
}
