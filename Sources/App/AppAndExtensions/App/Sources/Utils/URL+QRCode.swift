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

import UIKit

extension URL {
    
    func generateQRCode() -> CIImage? {
        guard let qrCodeGenerator = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        qrCodeGenerator.setValue(self.dataRepresentation, forKey: "inputMessage")
        let output = qrCodeGenerator.outputImage
        let colorParameters = [
            "inputColor0": CIColor(color: UIColor.black), // Foreground
            "inputColor1": CIColor(color: UIColor.clear) // Background
        ]
        let colored = output?.applyingFilter("CIFalseColor", parameters: colorParameters)
        return colored
    }

    func generateQRCode2() -> UIImage? {
        let context = CIContext()
        guard let qrCodeGenerator = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        qrCodeGenerator.setValue(self.dataRepresentation, forKey: "inputMessage")
        guard let output = qrCodeGenerator.outputImage else { return nil }
        guard let cgImage = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

}
