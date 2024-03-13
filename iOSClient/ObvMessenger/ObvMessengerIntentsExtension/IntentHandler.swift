/*
 *  Olvid for iOS
 *  Copyright © 2019-2024 Olvid SAS
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

/// The extension does nothing special for the moment. It is required though, as it allows to declare the `INStartCallIntent` in the `IntentsSupported` property list key of its `Info.plist` file.
/// By doing so, when the user starts an Olvid call from the list of "Recents" calls of the system "Phone" app,  the ``SceneDelegate.scene(_:continue:)`` method receives an intent of type `INStartCallIntent`.
/// Without this extension, the app entry point would receive a legacy (deprecated in iOS 13.0) `INStartAudioCallIntent` instead.
class IntentHandler: INExtension {

    override func handler(for intent: INIntent) -> Any {
        return self
    }

}
