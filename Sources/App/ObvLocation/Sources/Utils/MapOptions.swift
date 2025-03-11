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

import Foundation
import UIKit

@MainActor
enum MapOptions {
    case AppleMaps
    case GoogleMaps
    case Waze
    
    var appName: String {
        switch self {
        case .AppleMaps: return "Apple Maps"
        case .GoogleMaps: return "Google Maps"
        case .Waze: return "Waze"
        }
    }
    
    var baseURL: String {
        switch self {
        case .AppleMaps: return "http://maps.apple.com"
        case .GoogleMaps: return "comgooglemaps://"
        case .Waze: return "waze://"
        }
    }
    
    var url: URL? {
        return URL(string: self.baseURL)
    }
    
    var available: Bool {
        guard let url else { return false }
        return UIApplication.shared.canOpenURL(url)
    }
    
    static let allApps: [MapOptions] = [.AppleMaps, .GoogleMaps, .Waze]
    
    static var availableApps: [MapOptions] { allApps.filter(\.available) }
    
    func mapUrlString(latitude: Double, longitude: Double, address: String?) -> String {
        var urlString = self.baseURL
        
        let query = (address ?? MapOptions.Strings.mapPinTitle).addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? ""
        
        switch self {
        case .AppleMaps:
            urlString += "?q=\(query)?ll=\(latitude),\(longitude)"
        case .GoogleMaps:
            urlString += "?q=\(latitude),\(longitude)"
        case .Waze:
            urlString += "?ll=\(latitude),\(longitude)"
        }
        
        return urlString
    }
    
    func mapUrl(latitude: Double, longitude: Double, address: String?) -> URL? {
        let urlString = self.mapUrlString(latitude: latitude, longitude: longitude, address: address)
        return URL(string: urlString)
    }
    
    func openAt(latitude: Double, longitude: Double, address: String? = nil) {
        
        guard let url = self.mapUrl(latitude: latitude, longitude: longitude, address: address) else { return }
        
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
    
    static func mapAlertControllerAt(latitude: Double, longitude: Double, address: String? = nil) -> UIAlertController {
        let alertController = UIAlertController(title: MapOptions.Strings.mapAlertTitle, message: MapOptions.Strings.mapAlertMessage, preferredStyle: .actionSheet)
        
        for mapOption in MapOptions.availableApps {
            let action = UIAlertAction(title: mapOption.appName, style: .default) { action in
                mapOption.openAt(latitude: latitude, longitude: longitude, address: address)
            }
            alertController.addAction(action)
        }
        
        let cancelAction = UIAlertAction(title: MapOptions.Strings.mapAlertDismiss, style: .cancel, handler: nil)
        alertController.addAction(cancelAction)
        
        return alertController
    }
}

private extension MapOptions {
    
    struct Strings {
        static let mapPinTitle = String(localized: "MAP_PIN_TITLE", bundle: Bundle(for: ObvLocationResources.self))
        static let mapAlertTitle = String(localized: "MAP_ALERT_TITLE", bundle: Bundle(for: ObvLocationResources.self))
        static let mapAlertMessage = String(localized: "MAP_ALERT_MESSAGE", bundle: Bundle(for: ObvLocationResources.self))
        static let mapAlertDismiss = String(localized: "MAP_ALERT_DISMISS", bundle: Bundle(for: ObvLocationResources.self))
    }
    
}

