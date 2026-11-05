/*
 *  Olvid for iOS
 *  Copyright © 2019-2026 Olvid SAS
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


public enum SystemIcon: SymbolIcon, Sendable {

    case airplayaudio
    case airpods
    case airpodsmax
    case airpodspro
    case at
    case atCircle
    case atCircleFill
    case alarm
    case appBadge
    case appwindowSwipeRectangle
    case archivebox
    case archiveboxFill
    case arrowLeft
    case arrow2Squarepath
    case arrowClockwise
    case arrowClockwiseHeart
    case arrowCounterclockwise
    case arrowCounterclockwiseCircle
    case arrowCounterclockwiseCircleFill
    case arrowCounterclockwiseSquareFill
    case arrowDown
    case arrowDownCircle
    case arrowDownCircleFill
    case arrowDownRightAndArrowUpLeft
    case arrowDownToLine
    case arrowDownToLineCircle
    case arrowForward
    case arrowUpArrowDown
    case arrowUpArrowDownCircle
    case arrowUp
    case arrowTriangleheadClockwiseIcloudFill
    case arrowTriangleheadCounterclockwiseIcloud
    case arrowTriangleheadCounterclockwiseIcloudFill
    case arrowUpCircle
    case arrowUpCircleFill
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
    case barcodeViewfinder
    case bell(SystemIconFillOption)
    case bellBadge
    case bellBadgeSlash
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
    case chartBarYaxis
    case checkmark
    case checkmarkCircle
    case checkmarkCircleFill
    case checkmarkSealFill
    case checkmarkShield
    case checkmarkShieldFill
    case checkmarkSquareFill
    case chevronLeft
    case chevronLeftForwardslashChevronRight
    case chevronDown
    case chevronRight
    case chevronRightCircle
    case chevronRightCircleFill
    case chevronUp
    case chevronUpChevronDown
    case circle
    case circleCircle
    case circleDashed
    case circleFill
    case clock
    case cloud
    case cloudFill
    case creditcardFill
    case cursorarrowClick
    case cursorarrowClick2
    case desktopcomputerAndMacbook
    case desktopcomputer
    case display
    case docBadgeGearshape
    case doc
    case docFill
    case docOnClipboard
    case docOnClipboardFill
    case docOnDoc
    case docRichtext
    case earBadgeCheckmark
    case ellipsis
    case ellipsisCircle
    case ellipsisCircleFill
    case ellipsisRectangle
    case envelope
    case envelopeBadge
    case envelopeOpen
    case envelopeOpenFill
    case eraser
    case exclamationmarkCircle
    case exclamationmarkCircleFill
    case exclamationmarkBubble
    case exclamationmarkShieldFill
    case externaldrive
    case externaldriveFill
    case exclamationmarkTriangleFill
    case eyeFill
    case eyes
    case eye
    case eyeSlash
    case eyesInverse
    case faceSmiling
    case figureStandLineDottedFigureStand
    case figureTwoAndChildHoldinghands
    case fileMenuAndSelection
    case flame
    case flameFill
    case folder
    case folderCircle
    case folderFill
    case forwardFill
    case gear
    case gearshape
    case gearshapeFill
    case giftcardFill
    case globe
    case globeAmericasFill
    case globeAsiaAustraliaFill
    case globeEuropeAfricaFill
    case hammerCircle
    case handDraw
    case handTap
    case handThumbsup
    case handThumbsupFill
    case hare
    case headphones
    case hourglass
    case hourglassCircle
    case icloud(_: SystemIconFillOption = .none)
    case icloudAndArrowDown
    case infoCircle
    case infoCircleFill
    case infinity
    case ipad
    case ipadLandscape
    case iphone
    case iphoneAndArrowForwardInward
    case iphoneAndArrowForwardOutward
    case iphoneGen3CircleFill
    case iphoneRadiowavesLeftAndRight
    case laptopcomputerAndIphone
    case key
    case keyboard
    case keyFill
    case keySlash
    case lightbulbMax
    case line3Horizontal
    case link
    case location
    case locationFill
    case locationCircle
    case locationCircleFill
    case locationViewfinder
    case lock(_: SystemIconFillOption = .none, _: SystemIconShieldOption = .none)
    case lockRectangleOnRectangle
    case network
    case networkSlash
    case noteText
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
    case oneCircleFill
    case paperclip
    case paperclipCircle
    case paperclipCircleFill
    case paperplaneFill
    case pauseCircle
    case pauseFill
    case pencil(_: SystemIconCircleCircleFillOption? = nil)
    case pencilSlash
    case person
    case person2
    case person2Fill
    case person2Circle
    case person2SlashFill
    case person3
    case person3Fill
    case personBadgePlus
    case personBadgeShieldCheckmark
    case personBadgeShieldExclamationmark
    case personBust
    case personBustFill
    case personCropBadgeMagnifyingglass
    case personCropCircle
    case personCropCircleBadgeCheckmark
    case personCropCircleBadgeQuestionmark
    case personCropCircleBadgePlus
    case personCropCircleFillBadgeCheckmark
    case personCropCircleFillBadgeMinus
    case personCropCircleFillBadgePlus
    case personCropCircleFillBadgeXmark
    case personCropRectangle
    case personTextRectangle
    case personFillBadgeMinus
    case personFillBadgePlus
    case personFillQuestionmark
    case personFillViewfinder
    case personFillXmark
    case personLineDottedPerson
    case personLineDottedPersonFill
    case personSlash
    case phone
    case phoneArrowDownLeft
    case phoneArrowUpRight
    case phoneBubble
    case phoneCircleFill
    case phoneDownFill
    case phoneFill
    case phoneArrowDownLeftFill
    case phoneArrowUpRightFill
    case photo
    case photoBadgeExclamationMark
    case photoOnRectangleAngled
    case pin
    case pinFill
    case pinSlash
    case pinSlashFill
    case playCircle
    case playCircleFill
    case playFill
    case plus
    case plusCircle
    case power
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
    case rectangleStackBadgePlus
    case repeatIcon
    case repeatCircle
    case repeatCircleFill
    case restartCircle
    case scanner
    case serverRack
    case shieldFill
    case siri
    case shieldSlash
    case smartphone
    case speakerWave3Fill
    case speakerSlashFill
    case squareAndArrowDownOnSquare
    case squareAndArrowDown
    case squareAndArrowUp
    case squareAndPencil
    case star
    case starSlash
    case starFill
    case textformat
    case textBubble
    case textBubbleFill
    case timer
    case tortoise
    case trash
    case trashSlash
    case trashFill
    case trashCircle
    case tray
    case trayAndArrowDown
    case trayAndArrowUp
    case tv
    case uiwindowSplit2x1
    case umbrella
    case unpin
    case videoFill
    case videoFillSlash
    case visionpro
    case waveform
    case waveformCircle
    case wifi
    case xmark
    case xmarkCircle
    case xmarkCircleFill
    case xmarkOctagon
    case xmarkOctagonFill
    case xmarkSealFill
    case heart
    case heartSlash
    case heartSlashFill
    case stopFill
    case stopWatch
    case storefront
    case safari
    case wandAndSparkles
    case wrenchAdjustable
    case wrenchAdjustableFill
    case zipperPage
    case zzz

    public var name: String {
        switch self {
        case .lightbulbMax:
            if #available(iOS 17, *) {
                return "lightbulb.max"
            } else {
                return "lightbulb"
            }
        case .line3Horizontal:
            return "line.3.horizontal"
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
            return "photo.on.rectangle.angled"
        case .arrowLeft:
            return "arrow.left"
        case .arrowUp:
            return "arrow.up"
        case .arrowUpCircle:
            return "arrow.up.circle"
        case .arrowUpCircleFill:
            return "arrow.up.circle.fill"
        case .arrowUpLeftAndArrowDownRight:
            return "arrow.up.left.and.arrow.down.right"
        case .pauseCircle:
            return "pause.circle"
        case .pauseFill:
            return "pause.fill"
        case .arrowDownCircle:
            return "arrow.down.circle"
        case .arrowDownCircleFill:
            return "arrow.down.circle.fill"
        case .arrowDownRightAndArrowUpLeft:
            return "arrow.down.right.and.arrow.up.left"
        case .arrowDownToLine:
            return "arrow.down.to.line"
        case .arrowDownToLineCircle:
            return "arrow.down.to.line.circle"
        case .barcodeViewfinder:
            return "barcode.viewfinder"
        case .bell(let fillOptions):
            switch fillOptions {
            case .none:
                return "bell"

            case .fill:
                return "bell.fill"
            }
        case .hammerCircle:
            return "hammer.circle"
        case .handDraw:
            return "hand.draw"
        case .handTap:
            return "hand.tap"
        case .arrowshapeTurnUpLeftCircleFill:
            return "arrowshape.turn.up.left.circle.fill"
        case .arrowTriangle2CirclepathCamera:
            return "arrow.triangle.2.circlepath.camera"
        case .arrowTriangle2CirclepathCircle:
            return "arrow.triangle.2.circlepath.circle"
        case .arrowTriangle2CirclepathCircleFill:
            return "arrow.triangle.2.circlepath.circle.fill"
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
        case .trayAndArrowUp:
            return "tray.and.arrow.up"
        case .tv:
            return "tv"
        case .uiwindowSplit2x1:
            return "uiwindow.split.2x1"
        case .stopFill:
            return "stop.fill"
        case .stopWatch:
            return "stopwatch"
        case .storefront:
            if #available(iOS 17.0, *) {
                return "storefront"
            } else {
                return "house"
            }
        case .scanner:
            return "scanner"
        case .camera(let option):
            return "camera" + (option?.complement ?? "")
        case .chartBarYaxis:
            if #available(iOS 18, *) {
                return "chart.bar.yaxis"
            } else {
                return "chart.bar.xaxis"
            }
        case .car:
            return "car"
        case .photo:
            return "photo"
        case .photoBadgeExclamationMark:
            if #available(iOS 18.0, *) {
                return "photo.badge.exclamationmark"
            } else {
                return "exclamationmark.bubble.fill"
            }
        case .paperclip:
            return "paperclip"
        case .paperclipCircle:
            return "paperclip.circle"
        case .paperclipCircleFill:
            return "paperclip.circle.fill"
        case .trash:
            return "trash"
        case .arrowshapeTurnUpLeft2:
            return "arrowshape.turn.up.left.2"
        case .docOnClipboard:
            return "doc.on.clipboard"
        case .docOnClipboardFill:
            return "doc.on.clipboard.fill"
        case .docOnDoc:
            return "doc.on.doc"
        case .icloudAndArrowDown:
            return "icloud.and.arrow.down"
        case .infoCircle:
            return "info.circle"
        case .infoCircleFill:
            return "info.circle.fill"
        case .infinity:
            return "infinity"
        case .ipad:
            return "ipad"
        case .ipadLandscape:
            return "ipad.landscape"
        case .iphone:
            return "iphone"
        case .iphoneAndArrowForwardInward:
            if #available(iOS 18.0, *) {
                return "iphone.and.arrow.forward.inward"
            } else {
                return "iphone"
            }
        case .iphoneAndArrowForwardOutward:
            if #available(iOS 18.0, *) {
                return "iphone.and.arrow.forward.outward"
            } else {
                return "iphone"
            }
        case .iphoneGen3CircleFill:
            if #available(iOS 16.1, *) {
                return "iphone.gen3.circle.fill"
            } else {
                return "iphone"
            }
        case .iphoneRadiowavesLeftAndRight:
            return "iphone.radiowaves.left.and.right"
        case .laptopcomputerAndIphone:
        return "laptopcomputer.and.iphone"
        case .key:
            return "key"
        case .keyboard:
            return "keyboard"
        case .keyFill:
            return "key.fill"
        case .keySlash:
            if #available(iOS 17, *) {
                return "key.slash"
            } else {
                return "key"
            }
        case .personFillQuestionmark:
            return "person.fill.questionmark"
        case .personFillViewfinder:
            return "person.fill.viewfinder"
        case .personFillXmark:
            return "person.fill.xmark"
        case .personLineDottedPerson:
            return "person.line.dotted.person"
        case .personLineDottedPersonFill:
            return "person.line.dotted.person.fill"
        case .personSlash:
            if #available(iOS 17, *) {
                return "person.slash"
            } else {
                return "person.fill.xmark"
            }
        case .personBust:
            return "person.bust"
        case .personBustFill:
            return "person.bust.fill"
        case .personCropBadgeMagnifyingglass:
            if #available(iOS 18.0, *) {
                return "person.crop.badge.magnifyingglass"
            } else {
                return "person"
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
        case .hourglassCircle:
            return "hourglass.circle"
        case .folder:
            return "folder"
        case .folderCircle:
            return "folder.circle"
        case .arrowshapeTurnUpForward:
            return "arrowshape.turn.up.forward"
        case .arrowshapeTurnUpForwardCircleFill:
            return "arrowshape.turn.up.forward.circle.fill"
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
            return "arrow.clockwise.heart"
        case .arrowCounterclockwise:
            return "arrow.counterclockwise"
        case .arrowCounterclockwiseCircle:
            return "arrow.counterclockwise.circle"
        case .arrowCounterclockwiseCircleFill:
            return "arrow.counterclockwise.circle.fill"
        case .arrowCounterclockwiseSquareFill:
            if #available(iOS 17, *) {
                return "arrow.counterclockwise.square.fill"
            } else {
                return "arrow.counterclockwise.circle.fill"
            }
        case .questionmarkCircle:
            return "questionmark.circle"
        case .questionmarkCircleFill:
            return "questionmark.circle.fill"
        case .questionmarkSquare:
            return "questionmark.square"
        case .rectangleAndPencilAndEllipsis:
            return "rectangle.and.pencil.and.ellipsis"
        case .flame:
            return "flame"
        case .flameFill:
            return "flame.fill"
        case .cartFill:
            return "cart.fill"
        case .handThumbsup:
            return "hand.thumbsup"
        case .handThumbsupFill:
            return "hand.thumbsup.fill"
        case .arrowUturnForwardCircleFill:
            return "arrow.uturn.forward.circle.fill"
        case .clock:
            return "clock"
        case .cloud:
            return "cloud"
        case .cloudFill:
            return "cloud.fill"
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
        case .locationViewfinder:
            return "location.viewfinder"
        case .lock(let fill, let shield):
            return "lock" + shield.complement + fill.complement
        case .lockRectangleOnRectangle:
            return "lock.rectangle.on.rectangle"
        case .giftcardFill:
            return "giftcard.fill"
        case .globe:
            return "globe"
        case .globeAmericasFill:
            return "globe.americas.fill"
        case .globeAsiaAustraliaFill:
            return "globe.asia.australia.fill"
        case .globeEuropeAfricaFill:
            return "globe.europe.africa.fill"
        case .checkmarkShield:
            return "checkmark.shield"
        case .checkmarkShieldFill:
            return "checkmark.shield.fill"
        case .shieldSlash:
            return "shield.slash"
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
        case .gearshape:
            return "gearshape"
        case .gearshapeFill:
            return "gearshape.fill"
        case .earBadgeCheckmark:
            return "ear.badge.checkmark"
        case .figureStandLineDottedFigureStand:
            return "figure.stand.line.dotted.figure.stand"
        case .figureTwoAndChildHoldinghands:
            return "figure.2.and.child.holdinghands"
        case .fileMenuAndSelection:
            return "filemenu.and.selection"
        case .person3:
            return "person.3"
        case .person3Fill:
            return "person.3.fill"
        case .personBadgePlus:
            return "person.badge.plus"
        case .personBadgeShieldCheckmark:
            return "person.badge.shield.checkmark"
        case .personBadgeShieldExclamationmark:
            if #available(iOS 18, *) {
                return "person.badge.shield.exclamationmark"
            } else {
                return "person.badge.shield.checkmark"
            }
        case .chevronDown:
            return "chevron.down"
        case .chevronRight:
            return "chevron.right"
        case .chevronRightCircle:
            return "chevron.right.circle"
        case .chevronRightCircleFill:
            return "chevron.right.circle.fill"
        case .chevronUpChevronDown:
            return "chevron.up.chevron.down"
        case .chevronUp:
            return "chevron.up"
        case .textBubble:
            return "text.bubble"
        case .textBubbleFill:
            return "text.bubble.fill"
        case .phone:
            return "phone"
        case .phoneArrowDownLeft:
            return "phone.arrow.down.left"
        case .phoneArrowUpRight:
            return "phone.arrow.up.right"
        case .phoneBubble:
            if #available(iOS 17.0, *) {
                return "phone.bubble"
            } else {
                return "phone"
            }
        case .phoneCircleFill:
            return "phone.circle.fill"
        case .phoneDownFill:
            return "phone.down.fill"
        case .phoneFill:
            return "phone.fill"
        case .phoneArrowDownLeftFill:
            return "phone.arrow.down.left.fill"
        case .phoneArrowUpRightFill:
            return "phone.arrow.up.right.fill"
        case .ellipsis:
            return "ellipsis"
        case .ellipsisCircleFill:
            return "ellipsis.circle.fill"
        case .ellipsisCircle:
            return "ellipsis.circle"
        case .ellipsisRectangle:
            return "ellipsis.rectangle"
        case .pencil(let option):
            return "pencil" + (option?.complement ?? "")
        case .restartCircle:
            return "restart.circle"
        case .mappin:
            return "mappin"
        case .minusCircleFill:
            return "minus.circle.fill"
        case .micSlashFill:
            return "mic.slash.fill"
        case .minusCircle:
            return "minus.circle"
        case .arrowshapeTurnUpForwardFill:
            return "arrowshape.turn.up.forward.fill"
        case .personCropCircleBadgeCheckmark:
            return "person.crop.circle.badge.checkmark"
        case .personCropCircleBadgeQuestionmark:
            return "person.crop.circle.badge.questionmark"
        case .paperplaneFill:
            return "paperplane.fill"
        case .waveform:
            return "waveform"
        case .waveformCircle:
            return "waveform.circle"
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
        case .squareAndArrowDown:
            return "square.and.arrow.down"
        case .squareAndArrowUp:
            return "square.and.arrow.up"
        case .checkmarkCircleFill:
            return "checkmark.circle.fill"
        case .squareAndPencil:
            return "square.and.pencil"
        case .eyesInverse:
            return "eyes.inverse"
        case .faceSmiling:
            return "face.smiling"
        case .eyes:
            return "eyes"
        case .checkmarkSealFill:
            return "checkmark.seal.fill"
        case .arrowshapeTurnUpBackwardFill:
            return "arrowshape.turn.up.backward.fill"
        case .serverRack:
            return "server.rack"
        case .shieldFill:
            return "shield.fill"
        case .siri:
            return "siri"
        case .exclamationmarkCircle:
            return "exclamationmark.circle"
        case .exclamationmarkCircleFill:
            return "exclamationmark.circle.fill"
        case .exclamationmarkBubble:
            return "exclamationmark.bubble"
        case .exclamationmarkShieldFill:
            return "exclamationmark.shield.fill"
        case .externaldrive:
            return "externaldrive"
        case .externaldriveFill:
            return "externaldrive.fill"
        case .exclamationmarkTriangleFill:
            return "exclamationmark.triangle.fill"
        case .person:
            return "person"
        case .person2:
            return "person.2"
        case .person2Fill:
            return "person.2.fill"
        case .person2Circle:
            return "person.2.circle"
        case .person2SlashFill:
            return "person.2.slash.fill"
        case .personCropCircleFillBadgeCheckmark:
            return "person.crop.circle.fill.badge.checkmark"
        case .personCropCircleFillBadgeMinus:
            return "person.crop.circle.fill.badge.minus"
        case .personCropCircleFillBadgePlus:
            return "person.crop.circle.fill.badge.plus"
        case .personCropCircleFillBadgeXmark:
            return "person.crop.circle.fill.badge.xmark"
        case .bellBadge:
            return "bell.badge"
        case .bellBadgeSlash:
            if #available(iOS 17, *) {
                return "bell.badge.slash"
            } else {
                return "bell.slash"
            }
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
        case .arrowUpArrowDown:
            return "arrow.up.arrow.down"
        case .arrowUpArrowDownCircle:
            return "arrow.up.arrow.down.circle"
        case .arrowTriangleheadClockwiseIcloudFill:
            if #available(iOS 18, *) {
                return "arrow.trianglehead.clockwise.icloud.fill"
            } else {
                return "cloud.fill"
            }
        case .arrowTriangleheadCounterclockwiseIcloud:
            if #available(iOS 18, *) {
                return "arrow.trianglehead.counterclockwise.icloud"
            } else {
                return "cloud"
            }
        case .arrowTriangleheadCounterclockwiseIcloudFill:
            if #available(iOS 18, *) {
                return "arrow.trianglehead.counterclockwise.icloud.fill"
            } else {
                return "cloud.fill"
            }
        case .speakerSlashFill:
            return "speaker.slash.fill"
        case .plusCircle:
            return "plus.circle"
        case .power:
            return "power"
        case .poweroff:
            return "poweroff"
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
        case .playFill:
            return "play.fill"
        case .circleFill:
            return "circle.fill"
        case .circleDashed:
            return "circle.dashed"
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
            return "network"
        case .networkSlash:
            if #available(iOS 17.0, *) {
                return "network.slash"
            } else {
                return "network"
            }
        case .noteText:
            return "note.text"
        case .laptopcomputer:
            return "laptopcomputer"
        case .macbook:
            if #available(iOS 17.0, *) {
                return "macbook"
            } else {
                return "laptopcomputer"
            }
        case .macbookAndIphone:
            if #available(iOS 16.1, *) {
                return "macbook.and.iphone"
            } else {
                return "ipad.and.iphone"
            }
        case .magnifyingglass:
            return "magnifyingglass"
        case .star:
            return "star"
        case .starSlash:
            return "star.slash"
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
        case .circleCircle:
            return "circle.circle"
        case .archivebox:
            return "archivebox"
        case .archiveboxFill:
            return "archivebox.fill"
        case .doc:
            return "doc"
        case .docFill:
            return "doc.fill"
        case .rectangleDashedAndPaperclip:
            return "rectangle.dashed.and.paperclip"
        case .rectangleCompressVertical:
            return "rectangle.compress.vertical"
        case .envelope:
            return "envelope"
        case .envelopeBadge:
            return "envelope.badge"
        case .envelopeOpen:
            return "envelope.open"
        case .envelopeOpenFill:
            return "envelope.open.fill"
        case .eraser:
            return "eraser"
        case .smartphone:
            if #available(iOS 17.0, *) {
                return "smartphone"
            } else {
                return "candybarphone"
            }
        case .speakerWave3Fill:
            return "speaker.wave.3.fill"
        case .calendarBadgeClock:
            return "calendar.badge.clock"
        case .musicNoteList:
            return "music.note.list"
        case .oneCircleFill:
            return "1.circle.fill"
        case .personCropRectangle:
            return "person.crop.rectangle"
        case .personTextRectangle:
            return "person.text.rectangle"
        case .personFillBadgeMinus:
            return "person.fill.badge.minus"
        case .personFillBadgePlus:
            return "person.fill.badge.plus"
        case .calendar:
            return "calendar"
        case .bookmark:
            return "bookmark"
        case .cursorarrowClick:
            return "cursorarrow.click"
        case .cursorarrowClick2:
            return "cursorarrow.click.2"
        case .desktopcomputerAndMacbook:
            if #available(iOS 18.0, *) {
                return "desktopcomputer.and.macbook"
            } else {
                return "desktopcomputer"
            }
        case .desktopcomputer:
            return "desktopcomputer"
        case .display:
            return "display"
        case .rectangleSplit3x3:
            return "rectangle.split.3x3"
        case .rectangleStackBadgePlus:
            return "rectangle.stack.badge.plus"
        case .repeatIcon:
            return "repeat"
        case .repeatCircle:
            return "repeat.circle"
        case .repeatCircleFill:
            return "repeat.circle.fill"
        case .textformat:
            return "textformat"
        case .docBadgeGearshape:
            return "doc.badge.gearshape"
        case .chevronLeft:
            return "chevron.left"
        case .chevronLeftForwardslashChevronRight:
            return "chevron.left.forwardslash.chevron.right"
        case .alarm: return "alarm"
        case .appBadge:
            return "app.badge"
        case .appwindowSwipeRectangle:
            if #available(iOS 17, *) {
                return "appwindow.swipe.rectangle"
            } else {
                return "rectangle"
            }
        case .tortoise: return "tortoise"
        case .umbrella: return "umbrella"
        case .musicQuarterNote3:
            return "music.quarternote.3"
        case .pin: return "pin"
        case .pinFill: return "pin.fill"
        case .pinSlash:
            return "pin.slash"
        case .pinSlashFill: return "pin.slash.fill"
        case .unpin: return "pin.slash"
        case .videoFill:
            return "video.fill"
        case .videoFillSlash:
            return "video.slash.fill"
        case .visionpro:
            if #available(iOS 17.0, *) {
                return "visionpro"
            } else {
                return "eyeglasses"
            }
        case .safari: return "safari"
        case .wandAndSparkles:
            if #available(iOS 18, *) {
                return "wand.and.sparkles"
            } else {
                return "wand.and.rays"
            }
        case .wrenchAdjustable:
            return "wrench.adjustable"
        case .wrenchAdjustableFill:
            return "wrench.adjustable.fill"
        case .zipperPage:
            if #available(iOS 18, *) {
                return "zipper.page"
            } else {
                return "doc.zipper"
            }
        case .zzz:
            return "zzz"
        case .wifi:
            return "wifi"
        }
    }
}
