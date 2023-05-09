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


public enum SystemIcon: Hashable {

    case alarm
    case archiveboxFill
    case arrowClockwise
    case arrowCounterclockwise
    case arrowCounterclockwiseCircle
    case arrowCounterclockwiseCircleFill
    case arrowDown
    case arrowDownCircle
    case arrowDownCircleFill
    case arrowDownToLine
    case arrowDownToLineCircle
    case arrowForward
    case arrowUpArrowDownCircle
    case arrowUpCircle
    case arrowUturnForwardCircleFill
    case arrowshapeTurnUpBackwardFill
    case arrowshapeTurnUpForward
    case arrowshapeTurnUpForwardCircleFill
    case arrowshapeTurnUpForwardFill
    case arrowshapeTurnUpLeft2
    case arrowshapeTurnUpLeftCircleFill
    case arrowTriangle2CirclepathCircle
    case arrowTriangle2CirclepathCircleFill
    case book
    case bookmark
    case bubbleLeftAndBubbleRight
    case calendar
    case calendarBadgeClock
    case camera(_: SystemIconFillCircleCircleFillOption? = nil)
    case cartFill
    case checkmark
    case checkmarkCircle
    case checkmarkCircleFill
    case checkmarkSealFill
    case checkmarkShieldFill
    case checkmarkSquareFill
    case chevronLeftForwardslashChevronRight
    case chevronDown
    case chevronRight
    case chevronRightCircle
    case chevronRightCircleFill
    case circle
    case circleDashed
    case circleFill
    case clock
    case creditcardFill
    case display
    case docBadgeGearshape
    case docFill
    case docOnClipboardFill
    case docOnDoc
    case docRichtext
    case earBadgeCheckmark
    case ellipsisCircle
    case ellipsisCircleFill
    case ellipsisRectangle
    case envelopeOpenFill
    case exclamationmarkCircle
    case exclamationmarkShieldFill
    case eyeFill
    case eyes
    case eye
    case eyeSlash
    case eyesInverse
    case figureStandLineDottedFigureStand
    case flameFill
    case folderCircle
    case folderFill
    case forwardFill
    case gear
    case gearshapeFill
    case giftcardFill
    case hammerCircle
    case handTap
    case handThumbsup
    case handThumbsupFill
    case hare
    case hourglass
    case icloud(_: SystemIconFillOption = .none)
    case infoCircle
    case link
    case lock(_: SystemIconFillOption = .none, _: SystemIconShieldOption = .none)
    case network
    case micCircle
    case micCircleFill
    case micFill
    case minusCircle
    case minusCircleFill
    case moonZzzFill
    case multiply
    case muliplyCircleFill
    case musicQuarterNote3
    case musicNote
    case musicNoteList
    case paperclip
    case paperplaneFill
    case pauseCircle
    case pencil(_: SystemIconCircleCircleFillOption? = nil)
    case pencilSlash
    case person
    case person2
    case person2Fill
    case person2Circle
    case person3
    case person3Fill
    case personCropCircle
    case personCropCircleBadgeCheckmark
    case personCropCircleBadgeQuestionmark
    case personCropCircleBadgePlus
    case personCropCircleFillBadgeCheckmark
    case personCropCircleFillBadgeMinus
    case personCropCircleFillBadgeXmark
    case personTextRectangle
    case personFillQuestionmark
    case personFillViewfinder
    case personFillXmark
    case phoneCircleFill
    case phoneFill
    case photo
    case photoOnRectangleAngled
    case playCircle
    case playCircleFill
    case plus
    case plusCircle
    case qrcode
    case qrcodeViewfinder
    case questionmarkCircle
    case questionmarkCircleFill
    case rectangleAndPencilAndEllipsis
    case rectangleCompressVertical
    case rectangleSplit3x3
    case restartCircle
    case scanner
    case serverRack
    case shieldFill
    case speakerWave3Fill
    case speakerSlashFill
    case squareAndArrowUp
    case squareAndPencil
    case star
    case starFill
    case textformat
    case textBubbleFill
    case timer
    case tortoise
    case trash
    case trashFill
    case trashCircle
    case uiwindowSplit2x1
    case umbrella
    case xmark
    case xmarkCircle
    case xmarkCircleFill
    case xmarkOctagon
    case xmarkOctagonFill
    case heartSlashFill

    public var systemName: String {
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
        case .arrowDownCircleFill:
            return "arrow.down.circle.fill"
        case .arrowDownToLine:
            return "arrow.down.to.line"
        case .arrowDownToLineCircle:
            if #available(iOS 15, *) {
                return "arrow.down.to.line.circle"
            } else {
                return "arrow.down.to.line"
            }
        case .hammerCircle:
            if #available(iOS 15, *) {
                return "hammer.circle"
            } else {
                return "hammer"
            }
        case .handTap:
            if #available(iOS 14, *) {
                return "hand.tap"
            } else {
                return "hand.draw"
            }
        case .arrowshapeTurnUpLeftCircleFill:
            return "arrowshape.turn.up.left.circle.fill"
        case .arrowTriangle2CirclepathCircle:
            if #available(iOS 14, *) {
                return "arrow.triangle.2.circlepath.circle"
            } else {
                return "arrow.clockwise.circle"
            }
        case .arrowTriangle2CirclepathCircleFill:
            if #available(iOS 14, *) {
                return "arrow.triangle.2.circlepath.circle.fill"
            } else {
                return "arrow.clockwise.circle.fill"
            }
        case .trashFill:
            return "trash.fill"
        case .trashCircle:
            return "trash.circle"
        case .uiwindowSplit2x1:
            return "uiwindow.split.2x1"
        case .scanner:
            if #available(iOS 14, *) {
                return "scanner"
            } else {
                return "viewfinder.circle"
            }
        case .camera(let option):
            return "camera" + (option?.complement ?? "")
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
        case .eye:
            return "eye"
        case .eyeSlash:
            return "eye.slash"
        case .hare:
            return "hare"
        case .hourglass:
            return "hourglass"
        case .folderCircle:
            return "folder.circle"
        case .arrowshapeTurnUpForward:
            if #available(iOS 14, *) {
                return "arrowshape.turn.up.forward"
            } else {
                return "arrowshape.turn.up.right"
            }
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
        case .arrowCounterclockwise:
            return "arrow.counterclockwise"
        case .arrowCounterclockwiseCircle:
            return "arrow.counterclockwise.circle"
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
        case .clock:
            return "clock"
        case .creditcardFill:
            return "creditcard.fill"
        case .link:
            return "link"
        case .lock(let fill, let shield):
            return "lock" + shield.complement + fill.complement
        case .giftcardFill:
            if #available(iOS 14, *) {
                return "giftcard.fill"
            } else {
                return "checkmark"
            }
        case .checkmarkShieldFill:
            return "checkmark.shield.fill"
        case .icloud(let fill):
            return "icloud" + fill.complement
        case .folderFill:
            return "folder.fill"
        case .forwardFill:
            return "forward.fill"
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
        case .person3:
            return "person.3"
        case .person3Fill:
            return "person.3.fill"
        case .chevronDown:
            return "chevron.down"
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
        case .ellipsisRectangle:
            return "ellipsis.rectangle"
        case .pencil(let option):
            return "pencil" + (option?.complement ?? "")
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
        case .xmarkCircle:
            return "xmark.circle"
        case .xmarkCircleFill:
            return "xmark.circle.fill"
        case .xmarkOctagon:
            return "xmark.octagon"
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
        case .person2:
            return "person.2"
        case .person2Fill:
            return "person.2.fill"
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
        case .bubbleLeftAndBubbleRight:
            return "bubble.left.and.bubble.right"
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
        case .playCircleFill:
            return "play.circle.fill"
        case .circleFill:
            return "circle.fill"
        case .circleDashed:
            if #available(iOS 14.0, *) {
                return "circle.dashed"
            } else {
                return "circle"
            }
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
        case .star:
            return "star"
        case .starFill:
            return "star.fill"
        case .heartSlashFill:
            return "heart.slash.fill"
        case .circle:
            return "circle"
        case .archiveboxFill:
            return "archivebox.fill"
        case .docFill:
            return "doc.fill"
        case .rectangleCompressVertical:
            return "rectangle.compress.vertical"
        case .envelopeOpenFill:
            return "envelope.open.fill"
        case .speakerWave3Fill:
            if #available(iOS 14.0, *) {
                return "speaker.wave.3.fill"
            } else {
                return "speaker.3.fill"
            }
        case .calendarBadgeClock:
            if #available(iOS 14.0, *) {
                return "calendar.badge.clock"
            } else {
                return "calendar"
            }
        case .musicNoteList:
            return "music.note.list"
        case .personTextRectangle:
            if #available(iOS 15.0, *) {
                return "person.text.rectangle"
            } else {
                return "person.crop.circle"
            }
        case .calendar:
            return "calendar"
        case .bookmark:
            return "bookmark"
        case .display:
            if #available(iOS 14.0, *) {
                return "display"
            } else {
                return "desktopcomputer"
            }
        case .rectangleSplit3x3:
            return "rectangle.split.3x3"
        case .textformat:
            return "textformat"
        case .docBadgeGearshape:
            if #available(iOS 14.0, *) {
                return "doc.badge.gearshape"
            } else {
                return "gear"
            }
        case .chevronLeftForwardslashChevronRight:
            if #available(iOS 15.0, *) {
                return "chevron.left.forwardslash.chevron.right"
            } else {
                return "chevron.left.slash.chevron.right"
            }
        case .alarm: return "alarm"
        case .tortoise: return "tortoise"
        case .umbrella: return "umbrella"
        case .musicQuarterNote3:
            if #available(iOS 14.0, *) {
                return "music.quarternote.3"
            } else {
                return SystemIcon.musicNoteList.systemName
            }
        }
    }
}
