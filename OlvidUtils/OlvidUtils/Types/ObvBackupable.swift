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

public protocol ObvBackupable: AnyObject {

    var backupSource: ObvBackupableObjectSource { get }
    
    static var backupIdentifier: String { get }
    var backupIdentifier: String { get }

    func provideInternalDataForBackup(backupRequestIdentifier: FlowIdentifier, _ completionHandler: @escaping (Result<(internalJson: String, internalJsonIdentifier: String, source: ObvBackupableObjectSource), Error>) -> Void)
    func restoreBackup(backupRequestIdentifier: FlowIdentifier, internalJson: String, _ completionHandler: @escaping (Error?) -> Void)

}


public enum ObvBackupableObjectSource: Codable, CaseIterable {
    case engine
    case app
}
