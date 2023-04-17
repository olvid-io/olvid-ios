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

import SwiftUI


struct ImageEditor: View {

    @Binding var image: UIImage?

    @State var scale: CGFloat = 1.0
    @State var accumulatedScales: CGFloat = 1.0

    @State var offset: CGSize = CGSize.zero
    @State var accumulatedOffsets: CGSize = CGSize.zero

    private static var widthScale: CGFloat = 0.8
    private static var profilSize: CGFloat = 1080

    @State var orientation = UIDevice.current.orientation
    
    var completionHandler: () -> Void

    let orientationChanged = NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)
        .makeConnectable()
        .autoconnect()

    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            GeometryReader() { geo in
                let isPortrait = geo.size.height > geo.size.width
                let circleDiameter = (isPortrait ? geo.size.width : geo.size.height) * ImageEditor.widthScale
                if let image = image {
                    let geometry = Geometry(circleDiameter: circleDiameter, geo: geo, imageSize: image.size)
                    VStack(alignment: .center) {
                        Spacer()
                        HStack(alignment: .center) {
                            let base = Image(uiImage: image)
                                .resizable()
                                .aspectRatio(image.size, contentMode: .fill)
                                .frame(width: isPortrait ? geo.size.width * ImageEditor.widthScale : geo.size.width,
                                       height: isPortrait ? geo.size.height : geo.size.height * ImageEditor.widthScale)
                                .offset(offset)
                                .scaleEffect(scale)
                                .onAppear {
                                    scale = geometry.defaultScale
                                    accumulatedScales = scale
                                }
                            Spacer()
                            ZStack {
                                base
                                    .opacity(0.4)
                                    .blur(radius: 1.0)
                                base
                                    .opacity(0.55)
                                    .blur(radius: 0.4)
                                    .frame(width: circleDiameter, height: circleDiameter)
                                    .clipped()
                                base
                                    .clipShape(Circle())
                                    .gesture(MagnificationGesture()
                                                .onChanged { value in
                                                    let newScale = self.accumulatedScales * value
                                                    let defaultScale = geometry.defaultScale
                                                    guard newScale > defaultScale else { return }
                                                    if let fixedOffset = checkBounds(geometry: geometry,
                                                                                     newScale: newScale,
                                                                                     newOffset: offset) {
                                                        self.offset = fixedOffset
                                                    }
                                                    self.scale = newScale
                                                }
                                                .onEnded { value in
                                                    let newScale = self.accumulatedScales * value
                                                    let defaultScale = geometry.defaultScale
                                                    guard newScale > defaultScale else { return }
                                                    if let fixedOffset = checkBounds(geometry: geometry,
                                                                                     newScale: newScale,
                                                                                     newOffset: offset) {
                                                        self.offset = fixedOffset
                                                    }
                                                    self.scale = newScale
                                                    self.accumulatedScales = self.scale
                                                }
                                                .simultaneously(with: DragGesture()
                                                                    .onChanged { value in
                                                                        let newOffset = self.accumulatedOffsets + (value.translation / scale)
                                                                        let fixedOffset = checkBounds(geometry: geometry,
                                                                                                      newScale: scale,
                                                                                                      newOffset: newOffset) ?? newOffset
                                                                        self.offset = fixedOffset
                                                                    }
                                                                    .onEnded { value in
                                                                        let newOffset = self.accumulatedOffsets + (value.translation / scale)
                                                                        let fixedOffset = checkBounds(geometry: geometry,
                                                                                                      newScale: scale,
                                                                                                      newOffset: newOffset) ?? newOffset
                                                                        self.offset = fixedOffset
                                                                        self.accumulatedOffsets = self.offset
                                                                    }
                                                ))
                                    .onTapGesture(count: 2) {
                                        withAnimation {
                                            self.scale = geometry.defaultScale
                                            self.offset = CGSize.zero
                                            self.accumulatedScales = scale
                                            self.accumulatedOffsets = offset
                                        }
                                    }
                            }
                            Spacer()
                        }
                        Spacer()
                    }
                    .overlay(
                        HStack {
                            if let xmark = UIImage(systemName: "multiply.circle.fill") {
                                Button(action: {
                                    self.image = nil
                                    completionHandler()
                                }, label: {
                                    Image(uiImage: xmark)
                                        .resizable()
                                        .renderingMode(.template)
                                        .foregroundColor(.red)
                                        .scaledToFill()
                                        .frame(width: 44, height: 44)
                                        .padding(30)
                                })
                            }
                            Spacer()
                            if let checkmark = UIImage(systemName: "checkmark.circle.fill") {
                                Button(action: {
                                    if let scaledImage = buildImage(geometry: geometry, image: image, offset: offset, scale: scale) {
                                        self.image = scaledImage
                                        completionHandler()
                                    }
                                }, label: {
                                    Image(uiImage: checkmark)
                                        .resizable()
                                        .renderingMode(.template)
                                        .foregroundColor(.green)
                                        .scaledToFill()
                                        .frame(width: 44, height: 44)
                                        .padding(30)
                                })
                            }
                        }
                        ,alignment: .bottom)
                    .onReceive(orientationChanged) { _ in
                        self.orientation = UIDevice.current.orientation
                        self.scale = CGFloat.maximum(self.scale, geometry.defaultScale)
                    }
                }
            }
        }
    }

    private func buildImage(geometry: Geometry, image: UIImage, offset: CGSize, scale: CGFloat) -> UIImage? {
        let x = geometry.left(scale: scale, offset: offset) - geometry.radius
        let y = geometry.top(scale: scale, offset: offset) - geometry.radius

        let circleSize = CGSize(width: geometry.circleDiameter, height: geometry.circleDiameter)

        let origin = geometry.convertToPixel(x: x, y: y, scale: scale)
        let size = geometry.convertToPixel(size: circleSize, scale: scale)

        let cropZone = CGRect(x: origin.x, y: origin.y,
                              width: size.width, height: size.height)

        var result = image.croppedImage(inRect: cropZone)

        result = ImageEditor.resize(image: result, size: ImageEditor.profilSize)

        if let colorSpace = result.cgImage?.colorSpace?.name {
            if colorSpace != CGColorSpace.sRGB {
                result = ImageEditor.convertColorSpace(image: result, to: CGColorSpaceCreateDeviceRGB())
            }
        }

        return result
    }

    static func convertColorSpace(image: UIImage, to colorSpace: CGColorSpace) -> UIImage {
        guard let cgImage = image.cgImage else { assertionFailure(); return image }

        guard cgImage.colorSpace != colorSpace else { assertionFailure(); return image }

        let context = CGContext(data: nil, width: cgImage.width, height: cgImage.height, bitsPerComponent: cgImage.bitsPerComponent, bytesPerRow: cgImage.bytesPerRow, space: colorSpace, bitmapInfo: cgImage.bitmapInfo.rawValue)

        let size = CGSize(width: cgImage.width, height: cgImage.height)
        context?.draw(cgImage, in: CGRect(origin: .zero, size: size))

        guard let makeImage = context?.makeImage() else { assertionFailure(); return image }

        return UIImage(cgImage: makeImage, scale: image.scale, orientation: image.imageOrientation)
    }

    static func resize(image: UIImage, size newSize: CGFloat) -> UIImage {
        let currentSize = image.size
        guard currentSize.width > newSize else { return image }

        let newSize = CGSize(width: newSize / UIScreen.main.scale, height: newSize / UIScreen.main.scale)

        return UIGraphicsImageRenderer(size: newSize).image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    struct Geometry {

        let circleDiameter: CGFloat
        let geo: GeometryProxy
        let imageSize: CGSize

        var radius: CGFloat { circleDiameter / 2 }
        var imageRatio: CGFloat { imageSize.width / imageSize.height }
        var imageIsInPortrait: Bool { imageRatio < 1 }

        var isScreenInPortrait: Bool { geo.size.height > geo.size.width }

        func convertToPixel(x: CGFloat, y: CGFloat, scale: CGFloat) -> CGPoint {
            let imageSizeOnScreen = self.imageSizeOnScreen(scale: scale)

            let xRatio = x / imageSizeOnScreen.width
            let yRatio = y / imageSizeOnScreen.height

            return CGPoint(x: imageSize.width * xRatio, y: imageSize.height * yRatio)
        }

        func convertToPixel(size: CGSize, scale: CGFloat) -> CGSize {
            let imageSizeOnScreen = self.imageSizeOnScreen(scale: scale)

            let widthRatio = size.width / imageSizeOnScreen.width
            let heightRatio = size.height / imageSizeOnScreen.height

            return CGSize(width: imageSize.width * widthRatio, height: imageSize.height * heightRatio)
        }

        func imageSizeOnScreen(scale: CGFloat) -> CGSize {
            let imageHeight: CGFloat
            let imageWidth: CGFloat
            if (isScreenInPortrait) {
                imageHeight = scale * geo.size.height
                imageWidth = imageHeight * imageRatio
            } else {
                imageWidth = scale * geo.size.width
                imageHeight = imageWidth / imageRatio
            }
            return CGSize(width: imageWidth, height: imageHeight)
        }

        func top(scale: CGFloat, offset: CGSize) -> CGFloat {
            let imageHeight = imageSizeOnScreen(scale: scale).height
            return (imageHeight / 2) - (offset.height * scale)
        }

        func bottom(scale: CGFloat, offset: CGSize) -> CGFloat {
            let top = self.top(scale: scale, offset: offset)
            let imageHeight = imageSizeOnScreen(scale: scale).height
            return top - imageHeight
        }

        func left(scale: CGFloat, offset: CGSize) -> CGFloat {
            let imageWidth = imageSizeOnScreen(scale: scale).width
            return (imageWidth / 2) - (offset.width * scale)
        }

        func right(scale: CGFloat, offset: CGSize) -> CGFloat {
            let left = self.left(scale: scale, offset: offset)
            let imageWidth = imageSizeOnScreen(scale: scale).width
            return left - imageWidth
        }

        var defaultScale: CGFloat {
            if isScreenInPortrait {
                if imageIsInPortrait {
                    return (circleDiameter / geo.size.height) / imageRatio
                } else { // ImageInLandscape
                    return circleDiameter / geo.size.height
                }
            } else { // ScreenInLandscape
                if imageIsInPortrait {
                    return circleDiameter / geo.size.width
                } else { // ImageInLandscape
                    return circleDiameter / geo.size.width * imageRatio
                }
            }
        }


    }

    private func checkBounds(geometry: Geometry, newScale: CGFloat, newOffset: CGSize) -> CGSize? {
        var fixedOffset: CGSize? = nil

        let radius = geometry.radius

        let top = geometry.top(scale: newScale, offset: newOffset)
        if top < radius {
            if fixedOffset == nil { fixedOffset = newOffset }
            let correction = (radius - top) / newScale
            fixedOffset = CGSize(width: fixedOffset!.width,
                                 height: fixedOffset!.height - correction)
        }

        let bottom = geometry.bottom(scale: newScale, offset: newOffset)
        if bottom > -radius {
            if fixedOffset == nil { fixedOffset = newOffset }
            let correction = (bottom + radius) / newScale
            fixedOffset = CGSize(width: fixedOffset!.width,
                                 height: fixedOffset!.height + correction)
        }

        let left = geometry.left(scale: newScale, offset: newOffset)
        if left < radius {
            if fixedOffset == nil { fixedOffset = newOffset }
            let correction = (radius - left) / newScale
            fixedOffset = CGSize(width: fixedOffset!.width - correction,
                                 height: fixedOffset!.height)
        }

        let right = geometry.right(scale: newScale, offset: newOffset)
        if right > -radius {
            if fixedOffset == nil { fixedOffset = newOffset }
            let correction = (radius + right) / newScale
            fixedOffset = CGSize(width: fixedOffset!.width + correction,
                                 height: fixedOffset!.height)
        }

        return fixedOffset
    }

}


struct Landscape<Content>: View where Content: View {
    let content: () -> Content
    let height = UIScreen.main.bounds.width
    let width = UIScreen.main.bounds.height
    var body: some View {
        content().previewLayout(PreviewLayout.fixed(width: width, height: height))
    }
}

fileprivate extension CGSize {

    static func + (lhs: CGSize, rhs: CGSize) -> CGSize {
        return CGSize(width: lhs.width + rhs.width, height: lhs.height + rhs.height)
    }

    static func / (size: CGSize, denominator: CGFloat) -> CGSize {
        return CGSize(width: size.width / denominator, height: size.height / denominator)
    }

}

fileprivate extension UIImage {
    func croppedImage(inRect rect: CGRect) -> UIImage {
        var rectTransform: CGAffineTransform
        switch imageOrientation {
        case .left:
            let rotation = CGAffineTransform(rotationAngle: .pi / 2)
            rectTransform = rotation.translatedBy(x: 0, y: -size.height)
        case .right:
            let rotation = CGAffineTransform(rotationAngle: -.pi / 2)
            rectTransform = rotation.translatedBy(x: -size.width, y: 0)
        case .down:
            let rotation = CGAffineTransform(rotationAngle: -.pi)
            rectTransform = rotation.translatedBy(x: -size.width, y: -size.height)
        default:
            rectTransform = .identity
        }
        rectTransform = rectTransform.scaledBy(x: scale, y: scale)
        let transformedRect = rect.applying(rectTransform)
        let imageRef = cgImage!.cropping(to: transformedRect)!
        return UIImage(cgImage: imageRef, scale: scale, orientation: imageOrientation)
    }
}
