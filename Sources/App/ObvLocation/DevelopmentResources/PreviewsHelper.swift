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

import Foundation
import ObvTypes
import ObvCrypto
import ObvDesignSystem
import ObvAppTypes


extension ObvLocationCoordinate2D {
    static let eiffelTower: Self = .init(latitude: 48.858877739752266, longitude: 2.293690818092515)
}

extension ObvCryptoId {
    
    @MainActor
    static var sampleDatas: [Self] = [
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f0000b82ae0c57e570389cb03d5ad93dab4606bda7bbe01c09ce5e423094a8603a61e01693046e10e04606ef4461d31e1aa1819222a0a606a250e91749095a4410778c1")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f000009e171a9c73a0d6e9480b022154c83b13dfa8e4c99496c061c0c35b9b0432b3a014a5393f98a1aead77b813df0afee6b8af7e5f9a5aae6cb55fdb6bc5cc766f8da")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f00002d459c378a0bbc54c8be3e87e82d02347c046c4a50a6db25fe15751d8148671401054f3b14bbd7319a1f6d71746d6345332b92e193a9ea00880dd67b2f10352831")!),
        try! ObvCryptoId(identity: Data(hexString: "68747470733a2f2f7365727665722e6465762e6f6c7669642e696f000089aebda5ddb3a59942d4fe6e00720b851af1c2d70b6e24e41ac8da94793a6eb70136a23bf11bcd1ccc244ab3477545cc5fee6c60c2b89b8ff2fb339f7ed2ff1f0a")!),
    ]
    
}


extension UIImage {
    
    @MainActor
    static var sampleDatas: [UIImage] = [
        UIImage(named: "avatar00", in: ObvLocationResources.bundle, compatibleWith: nil)!,
        UIImage(named: "avatar01", in: ObvLocationResources.bundle, compatibleWith: nil)!,
        UIImage(named: "avatar02", in: ObvLocationResources.bundle, compatibleWith: nil)!,
        UIImage(named: "avatar03", in: ObvLocationResources.bundle, compatibleWith: nil)!,
        UIImage(named: "avatar04", in: ObvLocationResources.bundle, compatibleWith: nil)!,
        UIImage(named: "avatar05", in: ObvLocationResources.bundle, compatibleWith: nil)!,
    ]
    
    @MainActor
    static func avatarForCryptoId(cryptoId: ObvCryptoId) -> UIImage? {
        switch cryptoId {
        case ObvCryptoId.sampleDatas[0]:
            return UIImage.sampleDatas[0]
        case ObvCryptoId.sampleDatas[1]:
            return UIImage.sampleDatas[1]
        case ObvCryptoId.sampleDatas[2]:
            return UIImage.sampleDatas[2]
        case ObvCryptoId.sampleDatas[3]:
            return UIImage.sampleDatas[3]
        case ObvCryptoId.sampleDatas[4]:
            return UIImage.sampleDatas[4]
        case ObvCryptoId.sampleDatas[5]:
            return UIImage.sampleDatas[5]
        default:
            return nil
        }
    }
    
    @MainActor
    static func avatarForURL(url: URL) -> UIImage? {
        switch url {
        case  URL.sampleDatas[0]:
            return UIImage.sampleDatas[0]
        case  URL.sampleDatas[1]:
            return UIImage.sampleDatas[1]
        case  URL.sampleDatas[2]:
            return UIImage.sampleDatas[2]
        case  URL.sampleDatas[3]:
            return UIImage.sampleDatas[3]
        default:
            return nil
        }
    }

}


private extension ObvAvatarViewModel.Colors {
    
    @MainActor
    static var sampleDatas: [Self] = [
        .init(foreground: .systemBlue,
              background: .systemRed),
        .init(foreground: .systemPink,
              background: .systemCyan),
    ]
    
}


private extension URL {
    
    @MainActor
    static var sampleDatas: [Self] = [
        URL(string: "https://olvid.io/avatar00.png")!,
        URL(string: "https://olvid.io/avatar01.png")!,
        URL(string: "https://olvid.io/avatar02.png")!,
        URL(string: "https://olvid.io/avatar03.png")!,
        URL(string: "https://olvid.io/avatar04.png")!,
        URL(string: "https://olvid.io/avatar05.png")!,
    ]
    
    @MainActor
    static func sampleDataForCryptoId(cryptoId: ObvCryptoId) -> Self {
        switch cryptoId {
        case ObvCryptoId.sampleDatas[0]:
            return URL.sampleDatas[0]
        case ObvCryptoId.sampleDatas[1]:
            return URL.sampleDatas[1]
        case ObvCryptoId.sampleDatas[2]:
            return URL.sampleDatas[2]
        case ObvCryptoId.sampleDatas[3]:
            return URL.sampleDatas[3]
        default:
            return URL.sampleDatas[4]
        }
    }
    
}


private extension ObvAvatarViewModel {
    
    @MainActor
    static func sampleDatasForCryptoId(cryptoId: ObvCryptoId) -> Self {
        switch cryptoId {
        case ObvCryptoId.sampleDatas[0]:
            return ObvAvatarViewModel(characterOrIcon: .character("A"),
                                      colors: Colors.sampleDatas[0],
                                      photoURL: URL.sampleDataForCryptoId(cryptoId: cryptoId))
        case ObvCryptoId.sampleDatas[1]:
            return ObvAvatarViewModel(characterOrIcon: .character("B"),
                                      colors: Colors.sampleDatas[0],
                                      photoURL: URL.sampleDataForCryptoId(cryptoId: cryptoId))
        case ObvCryptoId.sampleDatas[2]:
            return ObvAvatarViewModel(characterOrIcon: .character("C"),
                                      colors: Colors.sampleDatas[0],
                                      photoURL: URL.sampleDataForCryptoId(cryptoId: cryptoId))
        case ObvCryptoId.sampleDatas[3]:
            return ObvAvatarViewModel(characterOrIcon: .character("D"),
                                      colors: Colors.sampleDatas[0],
                                      photoURL: URL.sampleDataForCryptoId(cryptoId: cryptoId))
        default:
            return ObvAvatarViewModel(characterOrIcon: .character("D"),
                                      colors: Colors.sampleDatas[0],
                                      photoURL: URL.sampleDataForCryptoId(cryptoId: cryptoId))
        }
    }
    
    @MainActor
    static var sampleDatas: [Self] = [
        .init(characterOrIcon: .character("A"),
              colors: Colors.sampleDatas[0],
              photoURL: URL.sampleDatas[0]),
        .init(characterOrIcon: .character("B"),
              colors: Colors.sampleDatas[0],
              photoURL: URL.sampleDatas[0]),
        .init(characterOrIcon: .character("C"),
              colors: Colors.sampleDatas[1],
              photoURL: URL.sampleDatas[0]),
        .init(characterOrIcon: .character("D"),
              colors: Colors.sampleDatas[1],
              photoURL: URL.sampleDatas[0]),
    ]
    
}


extension ObvContactIdentifier {
    
    @MainActor
    static var sampleDatas: [Self] = [
        .init(contactCryptoId: ObvCryptoId.sampleDatas[1], ownedCryptoId: ObvCryptoId.sampleDatas[0]),
        .init(contactCryptoId: ObvCryptoId.sampleDatas[2], ownedCryptoId: ObvCryptoId.sampleDatas[0]),
        .init(contactCryptoId: ObvCryptoId.sampleDatas[3], ownedCryptoId: ObvCryptoId.sampleDatas[0]),
    ]
    
}

extension UID {
    
    @MainActor
    static var sampleDatas: [UID] = [
        UID(uid: Data(repeating: 0x00, count: 32))!,
        UID(uid: Data(repeating: 0x01, count: 32))!,
        UID(uid: Data(repeating: 0x02, count: 32))!,
        UID(uid: Data(repeating: 0x03, count: 32))!,
        UID(uid: Data(repeating: 0x04, count: 32))!,
        UID(uid: Data(repeating: 0x05, count: 32))!,
    ]

}


extension ObvOwnedDeviceIdentifier {
    
    @MainActor
    static var sampleDatas: [Self] = [
        .init(ownedCryptoId: ObvCryptoId.sampleDatas[0], deviceUID: UID.sampleDatas[0]),
        .init(ownedCryptoId: ObvCryptoId.sampleDatas[0], deviceUID: UID.sampleDatas[1]),
    ]
    
}


extension ObvContactDeviceIdentifier {
    
    @MainActor
    static var sampleDatas: [Self] = [
        .init(contactIdentifier: ObvContactIdentifier.sampleDatas[0], deviceUID: UID.sampleDatas[2]),
        .init(contactIdentifier: ObvContactIdentifier.sampleDatas[1], deviceUID: UID.sampleDatas[3]),
        .init(contactIdentifier: ObvContactIdentifier.sampleDatas[2], deviceUID: UID.sampleDatas[4]),
    ]
    
}




extension ObvDeviceIdentifier {
    
    @MainActor
    static var sampleDatasOfOwnedDevices: [Self] = [
        .ownedDevice(ObvOwnedDeviceIdentifier.sampleDatas[0], isCurrentDevice: true),
        .ownedDevice(ObvOwnedDeviceIdentifier.sampleDatas[1], isCurrentDevice: false),
    ]

    @MainActor
    static var sampleDatasOfContactDevices: [Self] = [
        .contactDevice(ObvContactDeviceIdentifier.sampleDatas[0]),
        .contactDevice(ObvContactDeviceIdentifier.sampleDatas[1]),
        .contactDevice(ObvContactDeviceIdentifier.sampleDatas[2]),
    ]
    
}


extension ObvDeviceIdentifier {
    
    var cryptoId: ObvCryptoId {
        switch self {
        case .ownedDevice(let deviceIdentifier, isCurrentDevice: _):
            return deviceIdentifier.ownedCryptoId
        case .contactDevice(let contactDeviceIdentifier):
            return contactDeviceIdentifier.contactIdentifier.contactCryptoId
        }
    }
    
}


extension ObvMapViewModel.DeviceLocation {
    
    @MainActor
    static func sampleDatas(deviceIdentifier: ObvDeviceIdentifier) -> [Self] {
        switch deviceIdentifier {
        case ObvDeviceIdentifier.sampleDatasOfContactDevices[0]:
            return [
                .init(deviceIdentifier: deviceIdentifier,
                      coordinate: .eiffelTower,
                      avatarViewModel: ObvAvatarViewModel.sampleDatasForCryptoId(cryptoId: deviceIdentifier.cryptoId)),
                .init(deviceIdentifier: deviceIdentifier,
                      coordinate: .init(latitude: 48.871147, longitude: 2.324430),
                      avatarViewModel: ObvAvatarViewModel.sampleDatasForCryptoId(cryptoId: deviceIdentifier.cryptoId)),
                .init(deviceIdentifier: deviceIdentifier,
                      coordinate: .init(latitude: 48.867804, longitude: 2.333278),
                      avatarViewModel: ObvAvatarViewModel.sampleDatasForCryptoId(cryptoId: deviceIdentifier.cryptoId)),
                .init(deviceIdentifier: deviceIdentifier,
                      coordinate: .init(latitude: 48.868963, longitude: 2.312944),
                      avatarViewModel: ObvAvatarViewModel.sampleDatasForCryptoId(cryptoId: deviceIdentifier.cryptoId)),
            ]
        case ObvDeviceIdentifier.sampleDatasOfContactDevices[1]:
            return [
                .init(deviceIdentifier: deviceIdentifier,
                      coordinate: .init(latitude: 48.875694, longitude: 2.326956),
                      avatarViewModel: ObvAvatarViewModel.sampleDatasForCryptoId(cryptoId: deviceIdentifier.cryptoId)),
            ]
        default:
            return [
                .init(deviceIdentifier: deviceIdentifier,
                      coordinate: .eiffelTower,
                      avatarViewModel: ObvAvatarViewModel.sampleDatasForCryptoId(cryptoId: deviceIdentifier.cryptoId)),
            ]
        }
    }

}

extension ObvMapViewModel.CurrentOwnedDevice {
    
    @MainActor
    static var sampleData: Self {
        .init(deviceIdentifier: ObvDeviceIdentifier.sampleDatasOfOwnedDevices[0],
              avatarViewModel: ObvAvatarViewModel.sampleDatasForCryptoId(cryptoId: ObvDeviceIdentifier.sampleDatasOfOwnedDevices[0].cryptoId))
    }
    
}


extension ObvMapViewModel {
    
    @MainActor
    static var sampleDatas: [Self] = [
        .init(currentOwnedDevice: CurrentOwnedDevice.sampleData,
              deviceLocations: []),
        .init(currentOwnedDevice: CurrentOwnedDevice.sampleData,
              deviceLocations: [
                DeviceLocation.sampleDatas(deviceIdentifier: ObvDeviceIdentifier.sampleDatasOfContactDevices[0])[0],
                DeviceLocation.sampleDatas(deviceIdentifier: ObvDeviceIdentifier.sampleDatasOfContactDevices[1])[0],
              ]),
        .init(currentOwnedDevice: CurrentOwnedDevice.sampleData,
              deviceLocations: [
                DeviceLocation.sampleDatas(deviceIdentifier: ObvDeviceIdentifier.sampleDatasOfContactDevices[0])[0],
              ]),
    ]
    
}

extension ObvDiscussionIdentifier {
    @MainActor
    static var sampleDatas: [ObvDiscussionIdentifier] = [
        .groupV2(id: ObvGroupV2Identifier.sampleDatas[0])
        ]
}

extension ObvGroupV2Identifier {
    @MainActor
    static var sampleDatas: [Self] = [
        .init(ownedCryptoId: ObvCryptoId.sampleDatas[0], identifier: ObvGroupV2.Identifier.sampleDatas[0])
        ]
}

extension ObvGroupV2.Identifier {
    
    @MainActor
    static var sampleDatas: [Self] = [
        .init(groupUID: UID.sampleDatas[0], serverURL: URL(string: "https://olvid.io")!, category: .server)
        ]
    
}



//extension CircledInitialsConfiguration {
//    
//    @MainActor
//    static var sampleDatasForOwnedDevice: [Self] = [
//        .contact(initial: "ME",
//                 photo: .image(image: UIImage.avatarForCryptoId(cryptoId: ObvCryptoId.sampleDatas[0])),
//                 showGreenShield: false,
//                 showRedShield: false,
//                 cryptoId: ObvContactIdentifier.sampleDatas[0].contactCryptoId,
//                 tintAdjustementMode: .normal),
//    ]
//    
//    
//    @MainActor
//    static var sampleDatasForContactDevice: [Self] = [
//        .contact(initial: "A",
//                 photo: .image(image: UIImage.avatarForCryptoId(cryptoId: ObvCryptoId.sampleDatas[1])),
//                 showGreenShield: false,
//                 showRedShield: false,
//                 cryptoId: ObvContactIdentifier.sampleDatas[0].contactCryptoId,
//                 tintAdjustementMode: .normal),
//        .contact(initial: "B",
//                 photo: .image(image: UIImage.avatarForCryptoId(cryptoId: ObvCryptoId.sampleDatas[2])),
//                 showGreenShield: false,
//                 showRedShield: false,
//                 cryptoId: ObvContactIdentifier.sampleDatas[1].contactCryptoId,
//                 tintAdjustementMode: .normal),
//        .contact(initial: "C",
//                 photo: .image(image: UIImage.avatarForCryptoId(cryptoId: ObvCryptoId.sampleDatas[2])),
//                 showGreenShield: false,
//                 showRedShield: false,
//                 cryptoId: ObvContactIdentifier.sampleDatas[2].contactCryptoId,
//                 tintAdjustementMode: .normal),
//        .contact(initial: "d",
//                 photo: .image(image: UIImage.avatarForCryptoId(cryptoId: ObvCryptoId.sampleDatas[2])),
//                 showGreenShield: false,
//                 showRedShield: false,
//                 cryptoId: ObvContactIdentifier.sampleDatas[2].contactCryptoId,
//                 tintAdjustementMode: .normal),
//    ]
//    
//    @MainActor
//    static func sampleData(deviceIdentifier: ObvDeviceIdentifier) -> Self {
//        switch deviceIdentifier {
//
//        case ObvDeviceIdentifier.sampleDatasOfOwnedDevices[0]:
//            return CircledInitialsConfiguration.sampleDatasForOwnedDevice[0]
//
//        case ObvDeviceIdentifier.sampleDatasOfOwnedDevices[1]:
//            return CircledInitialsConfiguration.sampleDatasForOwnedDevice[0]
//
//        case ObvDeviceIdentifier.sampleDatasOfContactDevices[0]:
//            return CircledInitialsConfiguration.sampleDatasForContactDevice[0]
//
//        case ObvDeviceIdentifier.sampleDatasOfContactDevices[0]:
//            return CircledInitialsConfiguration.sampleDatasForContactDevice[1]
//
//        case ObvDeviceIdentifier.sampleDatasOfContactDevices[1]:
//            return CircledInitialsConfiguration.sampleDatasForContactDevice[2]
//
//        case ObvDeviceIdentifier.sampleDatasOfContactDevices[2]:
//            return CircledInitialsConfiguration.sampleDatasForContactDevice[3]
//
//        default:
//            return CircledInitialsConfiguration.sampleDatasForContactDevice[3]
//        }
//    }
//    
//}
