/*
 *  Olvid for iOS
 *  Copyright © 2019-2023 Olvid SAS
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


public extension UIDevice {
    
    private var currentDeviceCode: String {
        #if targetEnvironment(simulator)
        let machine = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "couldNotDetermineSimulatorModel"
        return machine
        #elseif targetEnvironment(macCatalyst)
        let service = IOServiceGetMatchingService(kIOMasterPortDefault,
                                                  IOServiceMatching("IOPlatformExpertDevice"))
        var modelIdentifier: String?
        if let modelData = IORegistryEntryCreateCFProperty(service, "model" as CFString, kCFAllocatorDefault, 0).takeRetainedValue() as? Data {
            modelIdentifier = String(data: modelData, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters)
        }

        IOObjectRelease(service)
        return modelIdentifier ?? "macCatalyst"
        #else
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafePointer(to: &systemInfo.machine) { unsafePointer in
            unsafePointer.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: unsafePointer)) { pointer in
                String(cString: pointer)
            }
        }
        return machine
        #endif
    }
    
    
    var preciseModel: String {
        debugPrint(currentDeviceCode)
        switch currentDeviceCode {

        // iPhones (restricting to specific models)
            
        case "iPhone8,1":
            return "iPhone 6s"
        case "iPhone8,2":
            return "iPhone 6s Plus"
        case "iPhone8,4":
            return "iPhone SE"
        case "iPhone9,1":
            return "iPhone 7"
        case "iPhone9,2":
            return "iPhone 7 Plus"
        case "iPhone9,3":
            return "iPhone 7"
        case "iPhone9,4":
            return "iPhone 7 Plus"
        case "iPhone10,1":
            return "iPhone 8"
        case "iPhone10,2":
            return "iPhone 8 Plus"
        case "iPhone10,3":
            return "iPhone X"
        case "iPhone10,4":
            return "iPhone 8"
        case "iPhone10,5":
            return "iPhone 8 Plus"
        case "iPhone10,6":
            return "iPhone X"
        case "iPhone11,2":
            return "iPhone XS"
        case "iPhone11,4":
            return "iPhone XS Max"
        case "iPhone11,6":
            return "iPhone XS Max"
        case "iPhone11,8":
            return "iPhone XR"
        case "iPhone12,1":
            return "iPhone 11"
        case "iPhone12,3":
            return "iPhone 11 Pro"
        case "iPhone12,5":
            return "iPhone 11 Pro Max"
        case "iPhone12,8":
            return "iPhone SE 2nd Gen"
        case "iPhone13,1":
            return "iPhone 12 Mini"
        case "iPhone13,2":
            return "iPhone 12"
        case "iPhone13,3":
            return "iPhone 12 Pro"
        case "iPhone13,4":
            return "iPhone 12 Pro Max"
        case "iPhone14,2":
            return "iPhone 13 Pro"
        case "iPhone14,3":
            return "iPhone 13 Pro Max"
        case "iPhone14,4":
            return "iPhone 13 Mini"
        case "iPhone14,5":
            return "iPhone 13"
        case "iPhone14,6":
            return "iPhone SE"
        case "iPhone14,7":
            return "iPhone 14"
        case "iPhone14,8":
            return "iPhone 14 Plus"
        case "iPhone15,2":
            return "iPhone 14 Pro"
        case "iPhone15,3":
            return "iPhone 14 Pro Max"
        case "iPhone15,4":
            return "iPhone 15"
        case "iPhone16,1":
            return "iPhone 15 Pro"
        case "iPhone15,5":
            return "iPhone 15 Plus"
        case "iPhone16,2":
            return "iPhone 15 Pro Max"
            
        case "Mac13,2":
            return "Mac Studio (2022)"
        case "Mac14,5", "Mac14,9":
            return "MacBook Pro (2023)"
        case "Mac14,6", "Mac14,10":
            return "MacBook Pro (2023)"
        case "Mac 14,7":
            return "MacBook Pro (2022)"
        case "MacBookPro18,3", "MacBookPro18,4":
            return "MacBook Pro (2021)"
        case "MacBookPro18,1", "MacBookPro18,2":
            return "MacBook Pro (2021)"
        case "MacBookPro17,1":
            return "MacBook Pro (2020)"
        case "MacBookPro16,3":
            return "MacBook Pro (2020)"
        case "MacBookPro16,2":
            return "MacBook Pro (2020)"
        case "MacBookPro16,1", "MacBookPro16,4":
            return "MacBook Pro (2020)"

        default:
            #if targetEnvironment(macCatalyst)
            return "Mac"
            #else
            return UIDevice.current.localizedModel
            #endif
        }
    }
    
}
