/*
 *  Olvid for iOS
 *  Copyright © 2019-2025 Olvid SAS
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

        //
        // iPhones (restricting to specific models)
        //

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
        case "iPhone15,5":
            return "iPhone 15 Plus"

        case "iPhone16,1":
            return "iPhone 15 Pro"
        case "iPhone16,2":
            return "iPhone 15 Pro Max"

        case "iPhone17,1":
            return "iPhone 16 Pro"
        case "iPhone17,2":
            return "iPhone 16 Pro Max"
        case "iPhone17,3":
            return "iPhone 16"
        case "iPhone17,4":
            return "iPhone 16 Plus"
        case "iPhone17,5":
            return "iPhone 16e"

        //
        // iPads
        //
            
        case "iPad1,1":
            return "iPad"
        case "iPad1,2":
            return "iPad" // 3G

        case "iPad2,1":
            return "iPad" // 2nd Gen
        case "iPad2,2":
            return "iPad" // 2nd Gen GSM
        case "iPad2,3":
            return "iPad" // 2nd Gen CDMA
        case "iPad2,4":
            return "iPad" // 2nd Gen New Revision
        case "iPad2,5":
            return "iPad mini"
        case "iPad2,6":
            return "iPad mini" // GSM+LTE
        case "iPad2,7":
            return "iPad mini" // CDMA+LTE
            
        case "iPad3,1":
            return "iPad" // 3rd Gen
        case "iPad3,2":
            return "iPad" // 3rd Gen CDMA
        case "iPad3,3":
            return "iPad" // 3rd Gen  GSM
        case "iPad3,4":
            return "iPad" // 4th Gen
        case "iPad3,5":
            return "iPad" // 4th Gen GSM+LTE
        case "iPad3,6":
            return "iPad" // 4th Gen CDMA+LTE
            
        case "iPad4,1":
            return "iPad Air" // WiFi
        case "iPad4,2":
            return "iPad Air" // GSM+CDMA
        case "iPad4,3":
            return "iPad Air" // 1st Gen (China)
        case "iPad4,4":
            return "iPad mini" // Retina (WiFi)
        case "iPad4,5":
            return "iPad mini" // Retina (GSM+CDMA)
        case "iPad4,6":
            return "iPad mini" // Retina (China)
        case "iPad4,7":
            return "iPad mini" // 3 WiFi
        case "iPad4,8":
            return "iPad mini" // 3 GSM+CDMA
        case "iPad4,9":
            return "iPad Mini" // 3 (China)
            
        case "iPad5,1":
            return "iPad mini" // 4 WiFi
        case "iPad5,2":
            return "iPad mini" // 4th Gen (WiFi+Cellular)
        case "iPad5,3":
            return "iPad Air" // 2 (WiFi)
        case "iPad5,4":
            return "iPad Air" // 2 (Cellular)
            
        case "iPad6,3":
            return "iPad Pro" // (9.7 inch, WiFi)
        case "iPad6,4":
            return "iPad Pro" //  (.7 inch, WiFi+LTE)
        case "iPad6,7":
            return "iPad Pro" // (12.9 inch, WiFi)
        case "iPad6,8":
            return "iPad Pro" //  (1.9 inch, WiFi+LTE)
        case "iPad6,11":
            return "iPad" // 2017
        case "iPad6,12":
            return "iPad" // 2017
            
        case "iPad7,1":
            return "iPad Pro" // 2nd Gen (WiFi)
        case "iPad7,2":
            return "iPad Pro" // 2nd Gen (WiFi+Cellular)
        case "iPad7,3":
            return "iPad Pro" // 10.5-inch 2nd Gen
        case "iPad7,4":
            return "iPad Pro" // 10.5-inch 2nd Gen
        case "iPad7,5":
            return "iPad" // 6th Gen (WiFi)
        case "iPad7,6":
            return "iPad" // 6th Gen (WiFi+Cellular)
        case "iPad7,11":
            return "iPad" // 7th Gen 10.2-inch (WiFi)
        case "iPad7,12":
            return "iPad" // 7th Gen 10.2-inch (WiFi+Cellular)
            
        case "iPad8,1":
            return "iPad Pro" // 11 inch 3rd Gen (WiFi)
        case "iPad8,2":
            return "iPad Pro" // 11 inch 3rd Gen (1TB, WiFi)
        case "iPad8,3":
            return "iPad Pro" // 11 inch 3rd Gen (WiFi+Cellular)
        case "iPad8,4":
            return "iPad Pro" // 11 inch 3rd Gen (1TB, WiFi+Cellular)
        case "iPad8,5":
            return "iPad Pro" // 12.9 inch 3rd Gen (WiFi)
        case "iPad8,6":
            return "iPad Pro" // 12.9 inch 3rd Gen (1TB, WiFi)
        case "iPad8,7":
            return "iPad Pro" // 12.9 inch 3rd Gen (WiFi+Cellular)
        case "iPad8,8":
            return "iPad Pro" // 12.9 inch 3rd Gen (1TB, WiFi+Cellular)
        case "iPad8,9":
            return "iPad Pro" // 11 inch 4th Gen (WiFi)
        case "iPad8,10":
            return "iPad Pro" // 11 inch 4th Gen (WiFi+Cellular)
        case "iPad8,11":
            return "iPad Pro" // 12.9 inch 4th Gen (WiFi)
        case "iPad8,12":
            return "iPad Pro" // 12.9 inch 4th Gen (WiFi+Cellular)

        case "iPad11,1":
            return "iPad mini" // 5th Gen (WiFi)
        case "iPad11,2":
            return "iPad mini" // 5th Gen
        case "iPad11,3":
            return "iPad Air" // 3rd Gen (WiFi)
        case "iPad11,4":
            return "iPad Air" // 3rd Gen
        case "iPad11,6":
            return "iPad" // 8th Gen (WiFi)
        case "iPad11,7":
            return "iPad" // 8th Gen (WiFi+Cellular)
            
        case "iPad12,1":
            return "iPad" // 9th Gen (WiFi)
        case "iPad12,2":
            return "iPad" // 9th Gen (WiFi+Cellular)
            
        case "iPad14,1":
            return "iPad mini" // 6th Gen (WiFi)
        case "iPad14,2":
            return "iPad mini" // 6th Gen (WiFi+Cellular)
          
        case "iPad13,1":
            return "iPad Air" // 4th Gen (WiFi)
        case "iPad13,2":
            return "iPad Air" // 4th Gen (WiFi+Cellular)
        case "iPad13,4":
            return "iPad Pro" // 11 inch 5th Gen
        case "iPad13,5":
            return "iPad Pro" // 11 inch 5th Gen
        case "iPad13,6":
            return "iPad Pro" // 11 inch 5th Gen
        case "iPad13,7":
            return "iPad Pro" // 11 inch 5th Gen
        case "iPad13,8":
            return "iPad Pro" // 12.9 inch 5th Gen
        case "iPad13,9":
            return "iPad Pro" // 12.9 inch 5th Gen
        case "iPad13,10":
            return "iPad Pro" // 12.9 inch 5th Gen
        case "iPad13,11":
            return "iPad Pro" // 12.9 inch 5th Gen
        case "iPad13,16":
            return "iPad Air" // 5th Gen (WiFi)
        case "iPad13,17":
            return "iPad Air" // 5th Gen (WiFi+Cellular)
        case "iPad13,18":
            return "iPad" // 10th generation
        case "iPad13,19":
            return "iPad" // 10th Gen

        case "iPad14,3":
            return "iPad Pro" // 11 inch 4th Gen
        case "iPad14,4":
            return "iPad Pro" // 11 inch 4th Gen
        case "iPad14,5":
            return "iPad Pro" // 12.9 inch 6th Gen
        case "iPad14,6":
            return "iPad Pro" // 12.9 inch 6th Gen
        case "iPad14,8":
            return "iPad Air" // 6th Gen
        case "iPad14,9":
            return "iPad Air" // 11-inch (M2)
        case "iPad14,10":
            return "iPad Air" // 7th Gen
        case "iPad14,11":
            return "iPad Air" // 13-inch (M2)

        case "iPad15,3":
            return "iPad Air" // iPad Air 11-inch 7th Gen (WiFi)
        case "iPad15,4":
            return "iPad Air" // iPad Air 11-inch 7th Gen (WiFi+Cellular)
        case "iPad15,5":
            return "iPad Air" // iPad Air 13-inch 7th Gen (WiFi)
        case "iPad15,6":
            return "iPad Air" // iPad Air 13-inch 7th Gen (WiFi+Cellular)
        case "iPad15,7":
            return "iPad 11th Gen" // iPad 11th Gen (WiFi)
        case "iPad15,8":
            return "iPad 11th Gen" // iPad 11th Gen (WiFi+Cellular)
            
        case "iPad16,1":
            return "iPad mini 7th Gen" // iPad mini 7th Gen (WiFi)
        case "iPad16,2":
            return "iPad mini 7th Gen" // iPad mini 7th Gen (WiFi+Cellular)
        case "iPad16,3":
            return "iPad Pro" // 11-inch 5th Gen
        case "iPad16,4":
            return "iPad Pro" // 11-inch (M4)
        case "iPad16,5":
            return "iPad Pro" // 13-inch 7th Gen
        case "iPad16,6":
            return "iPad Pro" // 13-inch (M4)
            
        //
        // Macs
        //
            
        case "MacBookPro16,3":
            return "MacBook Pro (2020)"
        case "MacBookPro16,2":
            return "MacBook Pro (2020)"
        case "MacBookPro16,1", "MacBookPro16,4":
            return "MacBook Pro (2020)"

        case "MacBookPro17,1":
            return "MacBook Pro (2020)"
            
        case "Macmini9,1":
            return "Apple Mac mini M1" // 2020

        case "MacBookPro18,3", "MacBookPro18,4":
            return "MacBook Pro (2021)"
        case "MacBookPro18,1", "MacBookPro18,2":
            return "MacBook Pro (2021)"

        case "Mac13,1":
            return "Mac Studio M1 Max" // 2022
        case "Mac13,2":
            return "Mac Studio M1 Ultra" // 2022

        case "Mac 14,7":
            return "MacBook Pro" // 2022

        case "Mac14,3":
            return "Apple Mac mini M2" // 2023
        case "Mac14,5":
            return "MacBook Pro" // 2023
        case "Mac14,6":
            return "MacBook Pro" // 2023
        case "Mac14,9":
            return "MacBook Pro" // 2023
        case "Mac14,10":
            return "MacBook Pro" // 2023
        case "Mac14,12":
            return "Apple Mac mini M2 Pro" // 2023
        case "Mac14,13":
            return "Mac Studio M2 Max" // 2023
        case "Mac14,14":
            return "Mac Studio M2 Ultra" // 2023

        default:
            #if targetEnvironment(macCatalyst)
            return "Mac"
            #else
            return UIDevice.current.localizedModel
            #endif
        }
    }
    
}
