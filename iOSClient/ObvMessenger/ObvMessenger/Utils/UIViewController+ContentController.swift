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

extension UIViewController {
    
    func displayContentController(content: UIViewController) {
        
        addChild(content)
        
        content.view.translatesAutoresizingMaskIntoConstraints = true
        content.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        content.view.frame = view.bounds
        
        view.addSubview(content.view)
        
        content.didMove(toParent: self)
    }
    
    
    func dismissContentController(content: UIViewController) {
        content.view.removeFromSuperview()
        content.removeFromParent()
    }
    
    
    func moveContentController(from previousContent: UIViewController, to nextContent: UIViewController, duration: Double = 0.9, options: UIView.AnimationOptions = [.transitionFlipFromLeft]) throws {
        
        guard children.contains(previousContent) else { throw NSError() }
        
        addChild(nextContent) // Automatic call to willMove(...)

        nextContent.view.translatesAutoresizingMaskIntoConstraints = true
        nextContent.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        nextContent.view.frame = view.bounds
        
        previousContent.willMove(toParent: nil)
        
        transition(from: previousContent, to: nextContent, duration: duration, options: options, animations: { }) { [weak self] (done) in
            
            previousContent.view.removeFromSuperview()
            previousContent.removeFromParent() // Automatic class to didMove(...) ?
            
            nextContent.didMove(toParent: self)
        }
        
    }
}
