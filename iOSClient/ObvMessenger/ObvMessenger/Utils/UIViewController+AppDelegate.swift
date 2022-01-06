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

import ObvEngine
import CoreData

extension UIViewController {
    
    var obvEngine: ObvEngine {
        var obvEngine: ObvEngine! = nil
        if Thread.isMainThread {
            let appDelegate = UIApplication.shared.delegate as! AppDelegate
            obvEngine = appDelegate.obvEngine
        } else {
            var appDelegate: AppDelegate! = nil
            DispatchQueue.main.sync {
                appDelegate = (UIApplication.shared.delegate as! AppDelegate)
                obvEngine = appDelegate.obvEngine
            }
        }
        return obvEngine
    }
}
