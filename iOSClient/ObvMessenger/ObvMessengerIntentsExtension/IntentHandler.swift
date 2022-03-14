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
  

import Intents

// The extension does nothing for the moment, we don't deal with Siri.
// We only use the extension to declare INStartCallIntent in IntentsSupported of Info.plist extension.
// This allow use to receive an interaction with INStartCallIntent in application(_ application: UIApplication, continue userActivity: NSUserActivity when the user tap on a call in iOS Recent Calls view.
// If we don't do it the entry point receives an INStartAudioCallIntent (that is deprecated in iOS 13.0) instead of INStartCallIntent.
class IntentHandler: INExtension {

    override func handler(for intent: INIntent) -> Any {
        return self
    }

}
