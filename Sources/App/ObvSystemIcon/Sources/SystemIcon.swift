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
 *  You should have received a copy of the GNU Affero General Public Licensecase a
 *  along with Olvid.  If not, see <https://www.gnu.org/licenses/>.
 */
  

import Foundation


public enum SystemIcon: SymbolIcon {

    case airplayaudio
    case airpods
    case airpodsmax
    case airpodspro
    case at
    case atCircle
    case atCircleFill
    case alarm
    case archivebox
    case archiveboxFill
    case arrowLeft
    case arrow2Squarepath
    case arrowClockwise
    case arrowClockwiseHeart
    case arrowCounterclockwise
    case arrowCounterclockwiseCircle
    case arrowCounterclockwiseCircleFill
    case arrowDown
    case arrowDownCircle
    case arrowDownCircleFill
    case arrowDownRightAndArrowUpLeft
    case arrowDownToLine
    case arrowDownToLineCircle
    case arrowForward
    case arrowUpArrowDownCircle
    case arrowUpCircle
    case arrowUpLeftAndArrowDownRight
    case arrowUturnForwardCircleFill
    case arrowshapeTurnUpBackwardFill
    case arrowshapeTurnUpForward
    case arrowshapeTurnUpForwardCircleFill
    case arrowshapeTurnUpForwardFill
    case arrowshapeTurnUpLeft2
    case arrowshapeTurnUpLeftCircleFill
    case arrowTriangle2CirclepathCamera
    case arrowTriangle2CirclepathCircle
    case arrowTriangle2CirclepathCircleFill
    case bell(SystemIconFillOption)
    case book
    case bookmark
    case bubble
    case bubbleLeft
    case bubbleLeftAndBubbleRight
    case bubbleLeftAndBubbleRightFill
    case calendar
    case calendarBadgeClock
    case camera(_: SystemIconFillCircleCircleFillOption? = nil)
    case car
    case cartFill
    case checkmark
    case checkmarkCircle
    case checkmarkCircleFill
    case checkmarkSealFill
    case checkmarkShield
    case checkmarkShieldFill
    case checkmarkSquareFill
    case chevronLeftForwardslashChevronRight
    case chevronDown
    case chevronRight
    case chevronRightCircle
    case chevronRightCircleFill
    case chevronUp
    case circle
    case circleDashed
    case circleFill
    case clock
    case creditcardFill
    case display
    case docBadgeGearshape
    case doc
    case docFill
    case docOnClipboardFill
    case docOnDoc
    case docRichtext
    case earBadgeCheckmark
    case ellipsisCircle
    case ellipsisCircleFill
    case ellipsisRectangle
    case envelope
    case envelopeBadge
    case envelopeOpenFill
    case exclamationmarkCircle
    case exclamationmarkBubble
    case exclamationmarkShieldFill
    case eyeFill
    case eyes
    case eye
    case eyeSlash
    case eyesInverse
    case faceSmiling
    case figureStandLineDottedFigureStand
    case flameFill
    case folder
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
    case headphones
    case hourglass
    case icloud(_: SystemIconFillOption = .none)
    case infoCircle
    case infinity
    case ipad
    case ipadLandscape
    case iphone
    case iphoneGen3CircleFill
    case laptopcomputerAndIphone
    case key
    case keySlash
    case link
    case location
    case locationFill
    case locationCircle
    case locationCircleFill
    case lock(_: SystemIconFillOption = .none, _: SystemIconShieldOption = .none)
    case lockRectangleOnRectangle
    case network
    case laptopcomputer
    case mappin
    case macbook
    case macbookAndIphone
    case magnifyingglass
    case micCircle
    case micCircleFill
    case mic
    case micFill
    case minusCircle
    case minusCircleFill
    case micSlashFill
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
    case personBadgePlus
    case personBadgeShieldCheckmark
    case personBadgeShieldExclamationmark
    case personCropCircle
    case personCropCircleBadgeCheckmark
    case personCropCircleBadgeQuestionmark
    case personCropCircleBadgePlus
    case personCropCircleFillBadgeCheckmark
    case personCropCircleFillBadgeMinus
    case personCropCircleFillBadgeXmark
    case personCropRectangle
    case personTextRectangle
    case personFillQuestionmark
    case personFillViewfinder
    case personFillXmark
    case personLineDottedPerson
    case personLineDottedPersonFill
    case phone
    case phoneArrowDownLeft
    case phoneArrowUpRight
    case phoneCircleFill
    case phoneDownFill
    case phoneFill
    case phoneArrowDownLeftFill
    case phoneArrowUpRightFill
    case photo
    case photoOnRectangleAngled
    case pin
    case pinFill
    case playCircle
    case playCircleFill
    case plus
    case plusCircle
    case poweroff
    case qrcode
    case qrcodeViewfinder
    case questionmarkCircle
    case questionmarkCircleFill
    case questionmarkSquare
    case rectangleAndPencilAndEllipsis
    /// Returns 􀥪 for iOS 14+ and 􀒖 for iOS 14>
    case rectangleDashedAndPaperclip
    case rectangleCompressVertical
    case rectangleSplit3x3
    case restartCircle
    case scanner
    case serverRack
    case shieldFill
    case speakerWave3Fill
    case speakerSlashFill
    case squareAndArrowDownOnSquare
    case squareAndArrowUp
    case squareAndPencil
    case star
    case starFill
    case textformat
    case textBubbleFill
    case timer
    case tortoise
    case trash
    case trashSlash
    case trashFill
    case trashCircle
    case tray
    case trayAndArrowDown
    case tv
    case uiwindowSplit2x1
    case umbrella
    case unpin
    case videoFill
    case visionpro
    case waveform
    case xmark
    case xmarkCircle
    case xmarkCircleFill
    case xmarkOctagon
    case xmarkOctagonFill
    case xmarkSealFill
    case heart
    case heartSlash
    case heartSlashFill
    case stopWatch
    case safari
    case zzz

    public var name: String {
        switch self {
        case .airplayaudio:
            return "airplayaudio"
        case .airpods:
            return "airpods"
        case .airpodsmax:
            return "airpodsmax"
        case .airpodspro:
            return "airpodspro"
        case .at:
            return "at"
        case .atCircle:
            return "at.circle"
        case .atCircleFill:
            return "at.circle.fill"
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
        case .arrowLeft:
            return "arrow.left"
        case .arrowUpCircle:
            return "arrow.up.circle"
        case .arrowUpLeftAndArrowDownRight:
            return "arrow.up.left.and.arrow.down.right"
        case .pauseCircle:
            return "pause.circle"
        case .arrowDownCircle:
            return "arrow.down.circle"
        case .arrowDownCircleFill:
            return "arrow.down.circle.fill"
        case .arrowDownRightAndArrowUpLeft:
            return "arrow.down.right.and.arrow.up.left"
        case .arrowDownToLine:
            return "arrow.down.to.line"
        case .arrowDownToLineCircle:
            if #available(iOS 15, *) {
                return "arrow.down.to.line.circle"
            } else {
                return "arrow.down.to.line"
            }
        case .bell(let fillOptions):
            switch fillOptions {
            case .none:
                return "bell"

            case .fill:
                return "bell.fill"
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
        case .arrowTriangle2CirclepathCamera:
            if #available(iOS 14, *) {
                return "arrow.triangle.2.circlepath.camera"
            } else {
                return "arrow.clockwise.circle.fill"
            }
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
        case .trashSlash:
            return "trash.slash"
        case .tray:
            return "tray"
        case .trayAndArrowDown:
            return "tray.and.arrow.down"
        case .tv:
            return "tv"
        case .uiwindowSplit2x1:
            return "uiwindow.split.2x1"
        case .stopWatch:
            return "stopwatch"
        case .scanner:
            if #available(iOS 14, *) {
                return "scanner"
            } else {
                return "viewfinder.circle"
            }
        case .camera(let option):
            return "camera" + (option?.complement ?? "")
        case .car:
            return "car"
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
        case .infinity:
            return "infinity"
        case .ipad:
            return "ipad"
        case .ipadLandscape:
            if #available(iOS 14.0, *) {
                return "ipad.landscape"
            } else {
                return "dot.square"
            }
        case .iphone:
            if #available(iOS 14.0, *) {
                return "iphone"
            } else {
                return "dot.square"
            }
        case .iphoneGen3CircleFill:
            if #available(iOS 16.1, *) {
                return "iphone.gen3.circle.fill"
            } else if #available(iOS 14, *) {
                return "iphone"
            } else {
                return "checkmark.circle"
            }
        case .laptopcomputerAndIphone:
        if #available(iOS 14, *) {
            return "laptopcomputer.and.iphone"
        } else {
            return "desktopcomputer"
        }
        case .key:
            return "key"
        case .keySlash:
            if #available(iOS 17, *) {
                return "key.slash"
            } else {
                return "key"
            }
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
        case .personLineDottedPerson:
            if #available(iOS 16, *) {
                return "person.line.dotted.person"
            } else {
                return "person.2"
            }
        case .personLineDottedPersonFill:
            if #available(iOS 16, *) {
                return "person.line.dotted.person.fill"
            } else {
                return "person.2.fill"
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
        case .headphones:
            return "headphones"
        case .hourglass:
            return "hourglass"
        case .folder:
            return "folder"
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
        case .arrow2Squarepath:
            return "arrow.2.squarepath"
        case .arrowClockwise:
            return "arrow.clockwise"
        case .arrowClockwiseHeart:
            if #available(iOS 14, *) {
                return "arrow.clockwise.heart"
            } else {
                return "heart"
            }
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
        case .questionmarkSquare:
            return "questionmark.square"
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
        case .location:
            return "location"
        case .locationFill:
            return "location.fill"
        case .locationCircle:
            return "location.circle"
        case .locationCircleFill:
            return "location.circle.fill"
        case .lock(let fill, let shield):
            return "lock" + shield.complement + fill.complement
        case .lockRectangleOnRectangle:
            return "lock.rectangle.on.rectangle"
        case .giftcardFill:
            if #available(iOS 14, *) {
                return "giftcard.fill"
            } else {
                return "checkmark"
            }
        case .checkmarkShield:
            return "checkmark.shield"
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
        case .personBadgePlus:
            return "person.badge.plus"
        case .personBadgeShieldCheckmark:
            if #available(iOS 16, *) {
                return "person.badge.shield.checkmark"
            } else {
                return "person"
            }
        case .personBadgeShieldExclamationmark:
            if #available(iOS 18, *) {
                return "person.badge.shield.exclamationmark"
            } else if #available(iOS 16, *) {
                return "person.badge.shield.checkmark"
            } else {
                return "person"
            }
        case .chevronDown:
            return "chevron.down"
        case .chevronRight:
            return "chevron.right"
        case .chevronRightCircle:
            return "chevron.right.circle"
        case .chevronRightCircleFill:
            return "chevron.right.circle.fill"
        case .chevronUp:
            return "chevron.up"
        case .textBubbleFill:
            return "text.bubble.fill"
        case .phone:
            return "phone"
        case .phoneArrowDownLeft:
            return "phone.arrow.down.left"
        case .phoneArrowUpRight:
            return "phone.arrow.up.right"
        case .phoneCircleFill:
            return "phone.circle.fill"
        case .phoneDownFill:
            return "phone.down.fill"
        case .phoneFill:
            return "phone.fill"
        case .phoneArrowDownLeftFill:
            if #available(iOS 16.0, *) {
                return "phone.arrow.down.left.fill"
            } else {
                return "phone.fill"
            }
        case .phoneArrowUpRightFill:
            if #available(iOS 16.0, *) {
                return "phone.arrow.up.right.fill"
            } else {
                return "phone.fill"
            }
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
        case .mappin:
            return "mappin"
        case .minusCircleFill:
            return "minus.circle.fill"
        case .micSlashFill:
            return "mic.slash.fill"
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
        case .waveform:
            return "waveform"
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
        case .xmarkSealFill:
            return "xmark.seal.fill"
        case .squareAndArrowDownOnSquare:
            return "square.and.arrow.down.on.square"
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
        case .faceSmiling:
            return "face.smiling"
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
        case .exclamationmarkBubble:
            return "exclamationmark.bubble"
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
        case .bubble:
            if #available(iOS 17, *) {
                return "bubble"
            } else {
                return "bubble.left"
            }
        case .bubbleLeft:
            return "bubble.left"
        case .bubbleLeftAndBubbleRight:
            return "bubble.left.and.bubble.right"
        case .bubbleLeftAndBubbleRightFill:
            return "bubble.left.and.bubble.right.fill"
        case .arrowUpArrowDownCircle:
            return "arrow.up.arrow.down.circle"
        case .speakerSlashFill:
            return "speaker.slash.fill"
        case .plusCircle:
            return "plus.circle"
        case .poweroff:
            if #available(iOS 14.0, *) {
                return "poweroff"
            } else {
                return "circle"
            }
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
        case .mic:
            return "mic"
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
        case .laptopcomputer:
            if #available(iOS 14.0, *) {
                return "laptopcomputer"
            } else {
                return "desktopcomputer"
            }
        case .macbook:
            if #available(iOS 17.0, *) {
                return "macbook"
            } else {
                return "laptopcomputer"
            }
        case .macbookAndIphone:
            if #available(iOS 16.1, *) {
                return "macbook.and.iphone"
            } else if #available(iOS 15.0, *) {
                return "ipad.and.iphone"
            } else {
                return "desktopcomputer"
            }
        case .magnifyingglass:
            return "magnifyingglass"
        case .star:
            return "star"
        case .starFill:
            return "star.fill"
        case .heart:
            return "heart"
        case .heartSlash:
            return "heart.slash"
        case .heartSlashFill:
            return "heart.slash.fill"
        case .circle:
            return "circle"
        case .archivebox:
            return "archivebox"
        case .archiveboxFill:
            return "archivebox.fill"
        case .doc:
            return "doc"
        case .docFill:
            return "doc.fill"
        case .rectangleDashedAndPaperclip:
            if #available(iOS 14, *) {
                return "rectangle.dashed.and.paperclip"
            } else {
                return "rectangle.and.paperclip"
            }
        case .rectangleCompressVertical:
            return "rectangle.compress.vertical"
        case .envelope:
            return "envelope"
        case .envelopeBadge:
            return "envelope.badge"
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
        case .personCropRectangle:
            return "person.crop.rectangle"
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
                return SystemIcon.musicNoteList.name
            }
        case .pin: return "pin"
        case .pinFill: return "pin.fill"
        case .unpin: return "pin.slash"
        case .videoFill:
            return "video.fill"
        case .visionpro:
            if #available(iOS 17.0, *) {
                return "visionpro"
            } else {
                return "eyeglasses"
            }
        case .safari: return "safari"
        case .zzz:
            return "zzz"
        }
    }
}
