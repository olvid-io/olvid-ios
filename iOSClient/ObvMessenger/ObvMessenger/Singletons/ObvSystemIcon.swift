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

import Foundation
import SwiftUI
import CryptoKit


enum ObvSystemIcon {

    case arrowClockwise
    case arrowCounterclockwiseCircleFill
    case arrowDown
    case arrowDownCircle
    case arrowForward
    case arrowUpArrowDownCircle
    case arrowUpCircle
    case arrowUturnForwardCircleFill
    case arrowshapeTurnUpBackwardFill
    case arrowshapeTurnUpForwardCircleFill
    case arrowshapeTurnUpForwardFill
    case arrowshapeTurnUpLeft2
    case arrowshapeTurnUpLeftCircleFill
    case book
    case camera
    case cartFill
    case checkmark
    case checkmarkCircle
    case checkmarkCircleFill
    case checkmarkSealFill
    case checkmarkShieldFill
    case checkmarkSquareFill
    case chevronRight
    case chevronRightCircle
    case chevronRightCircleFill
    case circleFill
    case creditcardFill
    case docOnClipboardFill
    case docOnDoc
    case docRichtext
    case earBadgeCheckmark
    case ellipsisCircle
    case ellipsisCircleFill
    case exclamationmarkCircle
    case exclamationmarkShieldFill
    case eyeFill
    case eyes
    case eyesInverse
    case figureStandLineDottedFigureStand
    case flameFill
    case folderCircle
    case folderFill
    case gear
    case gearshapeFill
    case giftcardFill
    case handTap
    case handThumbsup
    case handThumbsupFill
    case hare
    case hourglass
    case icloudFill
    case infoCircle
    case link
    case lockFill
    case network
    case micCircle
    case micCircleFill
    case micFill
    case minusCircle
    case minusCircleFill
    case moonZzzFill
    case multiply
    case muliplyCircleFill
    case musicNote
    case paperclip
    case paperplaneFill
    case pauseCircle
    case pencilCircle
    case pencilCircleFill
    case pencilSlash
    case person
    case person2Circle
    case person3Fill
    case personCropCircle
    case personCropCircleBadgeCheckmark
    case personCropCircleBadgeQuestionmark
    case personCropCircleBadgePlus
    case personCropCircleFillBadgeCheckmark
    case personCropCircleFillBadgeMinus
    case personCropCircleFillBadgeXmark
    case personFillQuestionmark
    case personFillViewfinder
    case personFillXmark
    case phoneCircleFill
    case phoneFill
    case photo
    case photoOnRectangleAngled
    case playCircle
    case plus
    case plusCircle
    case qrcode
    case qrcodeViewfinder
    case questionmarkCircle
    case questionmarkCircleFill
    case rectangleAndPencilAndEllipsis
    case restartCircle
    case scanner
    case serverRack
    case shieldFill
    case speakerSlashFill
    case squareAndArrowUp
    case squareAndPencil
    case textBubbleFill
    case timer
    case trash
    case trashCircle
    case xmark
    case xmarkCircleFill
    case xmarkOctagonFill

    var systemName: String {
        switch self {
        case .timer:
            return "timer"
        case .docRichtext:
            return "doc.richtext"
        case .photoOnRectangleAngled:
            if #available(iOS 14, *) {
                return "photo.on.rectangle.angled"
            } else {
                return "photo.on.rectangle"
            }
        case .arrowUpCircle:
            return "arrow.up.circle"
        case .pauseCircle:
            return "pause.circle"
        case .arrowDownCircle:
            return "arrow.down.circle"
        case .handTap:
            if #available(iOS 14, *) {
                return "hand.tap"
            } else {
                return "hand.draw"
            }
        case .arrowshapeTurnUpLeftCircleFill:
            return "arrowshape.turn.up.left.circle.fill"
        case .trashCircle:
            return "trash.circle"
        case .scanner:
            if #available(iOS 14, *) {
                return "scanner"
            } else {
                return "viewfinder.circle"
            }
        case .camera:
            return "camera"
        case .photo:
            return "photo"
        case .paperclip:
            return "paperclip"
        case .trash:
            return "trash"
        case .arrowshapeTurnUpLeft2:
            return "arrowshape.turn.up.left.2"
        case .docOnClipboardFill:
            return "doc.on.clipboard.fill"
        case .docOnDoc:
            return "doc.on.doc"
        case .infoCircle:
            return "info.circle"
        case .personFillQuestionmark:
            if #available(iOS 14, *) {
                return "person.fill.questionmark"
            } else {
                return "person.fill"
            }
        case .personFillViewfinder:
            if #available(iOS 14, *) {
                return "person.fill.viewfinder"
            } else {
                return "qrcode.viewfinder"
            }
        case .personFillXmark:
            if #available(iOS 14, *) {
                return "person.fill.xmark"
            } else {
                return "qrcode.viewfinder"
            }
        case .personCropCircleBadgePlus:
            return "person.crop.circle.badge.plus"
        case .eyeFill:
            return "eye.fill"
        case .hare:
            return "hare"
        case .hourglass:
            return "hourglass"
        case .folderCircle:
            return "folder.circle"
        case .arrowshapeTurnUpForwardCircleFill:
            if #available(iOS 14, *) {
                return "arrowshape.turn.up.forward.circle.fill"
            } else {
                return "arrowshape.turn.up.right.circle.fill"
            }
        case .personCropCircle:
            return "person.crop.circle"
        case .checkmark:
            return "checkmark"
        case .checkmarkCircle:
            return "checkmark.circle"
        case .qrcodeViewfinder:
            return "qrcode.viewfinder"
        case .arrowClockwise:
            return "arrow.clockwise"
        case .arrowCounterclockwiseCircleFill:
            return "arrow.counterclockwise.circle.fill"
        case .questionmarkCircle:
            return "questionmark.circle"
        case .questionmarkCircleFill:
            return "questionmark.circle.fill"
        case .rectangleAndPencilAndEllipsis:
            if #available(iOS 14, *) {
                return "rectangle.and.pencil.and.ellipsis"
            } else {
                return "square.and.pencil"
            }
        case .flameFill:
            return "flame.fill"
        case .cartFill:
            return "cart.fill"
        case .handThumbsup:
            return "hand.thumbsup"
        case .handThumbsupFill:
            return "hand.thumbsup.fill"
        case .arrowUturnForwardCircleFill:
            if #available(iOS 14, *) {
                return "arrow.uturn.forward.circle.fill"
            } else {
                return "arrow.uturn.right.circle.fill"
            }
        case .creditcardFill:
            return "creditcard.fill"
        case .link:
            return "link"
        case .lockFill:
            return "lock.fill"
        case .giftcardFill:
            if #available(iOS 14, *) {
                return "giftcard.fill"
            } else {
                return "checkmark"
            }
        case .checkmarkShieldFill:
            return "checkmark.shield.fill"
        case .icloudFill:
            return "icloud.fill"
        case .folderFill:
            return "folder.fill"
        case .qrcode:
            return "qrcode"
        case .gear:
            return "gear"
        case .gearshapeFill:
            if #available(iOS 14, *) {
                return "gearshape.fill"
            } else {
                return "gear"
            }
        case .earBadgeCheckmark:
            if #available(iOS 14, *) {
                return "ear.badge.checkmark"
            } else {
                return "ear"
            }
        case .figureStandLineDottedFigureStand:
            if #available(iOS 14, *) {
                return "figure.stand.line.dotted.figure.stand"
            } else {
                return "person.2.fill"
            }
        case .person3Fill:
            return "person.3.fill"
        case .chevronRight:
            return "chevron.right"
        case .chevronRightCircle:
            return "chevron.right.circle"
        case .chevronRightCircleFill:
            return "chevron.right.circle.fill"
        case .textBubbleFill:
            return "text.bubble.fill"
        case .phoneCircleFill:
            return "phone.circle.fill"
        case .phoneFill:
            return "phone.fill"
        case .ellipsisCircleFill:
            return "ellipsis.circle.fill"
        case .ellipsisCircle:
            return "ellipsis.circle"
        case .pencilCircle:
            return "pencil.circle"
        case .pencilCircleFill:
            return "pencil.circle.fill"
        case .restartCircle:
            if #available(iOS 14, *) {
                return "restart.circle"
            } else {
                return "arrowtriangle.left.circle"
            }
        case .minusCircleFill:
            return "minus.circle.fill"
        case .minusCircle:
            return "minus.circle"
        case .arrowshapeTurnUpForwardFill:
            if #available(iOS 14, *) {
                return "arrowshape.turn.up.forward.fill"
            } else {
                return "arrowshape.turn.up.right.fill"
            }
        case .personCropCircleBadgeCheckmark:
            return "person.crop.circle.badge.checkmark"
        case .personCropCircleBadgeQuestionmark:
            if #available(iOS 14, *) {
                return "person.crop.circle.badge.questionmark"
            } else {
                return "person.crop.circle"
            }
        case .paperplaneFill:
            return "paperplane.fill"
        case .xmark:
            return "xmark"
        case .xmarkCircleFill:
            return "xmark.circle.fill"
        case .xmarkOctagonFill:
            return "xmark.octagon.fill"
        case .squareAndArrowUp:
            return "square.and.arrow.up"
        case .checkmarkCircleFill:
            return "checkmark.circle.fill"
        case .squareAndPencil:
            return "square.and.pencil"
        case .eyesInverse:
            if #available(iOS 14, *) {
                return "eyes.inverse"
            } else {
                return "eyeglasses"
            }
        case .eyes:
            if #available(iOS 14, *) {
                return "eyes"
            } else {
                return "eyeglasses"
            }
        case .checkmarkSealFill:
            return "checkmark.seal.fill"
        case .arrowshapeTurnUpBackwardFill:
            if #available(iOS 14, *) {
                return "arrowshape.turn.up.backward.fill"
            } else {
                return "arrowshape.turn.up.left.fill"
            }
        case .serverRack:
            if #available(iOS 14, *) {
                return "server.rack"
            } else {
                return "personalhotspot"
            }
        case .shieldFill:
            return "shield.fill"
        case .exclamationmarkCircle:
            return "exclamationmark.circle"
        case .exclamationmarkShieldFill:
            return "exclamationmark.shield.fill"
        case .person:
            return "person"
        case .person2Circle:
            if #available(iOS 14, *) {
                return "person.2.circle"
            } else {
                return "person.2"
            }
        case .personCropCircleFillBadgeCheckmark:
            return "person.crop.circle.fill.badge.checkmark"
        case .personCropCircleFillBadgeMinus:
            return "person.crop.circle.fill.badge.minus"
        case .personCropCircleFillBadgeXmark:
            return "person.crop.circle.fill.badge.xmark"
        case .book:
            return "book"
        case .arrowUpArrowDownCircle:
            return "arrow.up.arrow.down.circle"
        case .speakerSlashFill:
            return "speaker.slash.fill"
        case .plusCircle:
            return "plus.circle"
        case .arrowForward:
           return "arrow.forward"
        case .pencilSlash:
            return "pencil.slash"
        case .checkmarkSquareFill:
            return "checkmark.square.fill"
        case .micCircle:
            return "mic.circle"
        case .micCircleFill:
            return "mic.circle.fill"
        case .micFill:
            return "mic.fill"
        case .playCircle:
            return "play.circle"
        case .circleFill:
            return "circle.fill"
        case .muliplyCircleFill:
            return "multiply.circle.fill"
        case .musicNote:
            return "music.note"
        case .moonZzzFill:
            return "moon.zzz.fill"
        case .multiply:
            return "multiply"
        case .plus:
            return "plus"
        case .arrowDown:
            return "arrow.down"
        case .network:
            if #available(iOS 14.0, *) {
                return "network"
            } else {
                return "link"
            }
        }
    }
}


@available(iOS 13, *)
extension Image {

    init(systemIcon: ObvSystemIcon) {
        self.init(systemName: systemIcon.systemName)
    }

}

@available(iOS 13.0, *)
extension UIImage {

    convenience init?(systemIcon: ObvSystemIcon, withConfiguration configuration: UIImage.Configuration? = nil) {
        self.init(systemName: systemIcon.systemName, withConfiguration: configuration)

    }

}

@available(iOS 14.0, *)
extension Label where Title == Text, Icon == Image {

    init(_ titleKey: LocalizedStringKey, systemIcon icon: ObvSystemIcon) {
        self.init(titleKey, systemImage: icon.systemName)
    }

    init<S>(_ title: S, systemIcon icon: ObvSystemIcon) where S: StringProtocol {
        self.init(title, systemImage: icon.systemName)
    }

}
