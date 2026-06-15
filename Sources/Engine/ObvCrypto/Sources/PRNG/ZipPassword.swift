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
 *  You should have received a copy of the GNU Affero General Public License
 *  along with Olvid.  If not, see <https://www.gnu.org/licenses/>.
 */

import Foundation

/// A `ZipPassword` is a password intended to be used as an encryption key to encrypt a zip when it is created.
public struct ZipPassword {

    private static let acceptableCharacters: [Character] = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")

    /// Generates a zip password of the form `xxxxxx-xxxxxx-xxxxxx` using the given PRNG.
    public static func generate(with prng: PRNG) -> String {
        let groupSize = 6
        let groupCount = 3
        let total = groupSize * groupCount

        var characters: [Character] = []
        characters.reserveCapacity(total)

        while characters.count < total {
            let byte = prng.genBytes(count: 1).first!
            let index = Int(byte)
            guard index < acceptableCharacters.count else { continue }
            let randomCharacter = acceptableCharacters[index]
            characters.append(randomCharacter)
        }
        
        var result = ""
        result.reserveCapacity(total + groupCount - 1)
        for groupIndex in 0..<groupCount {
            if groupIndex > 0 { result.append("-") }
            for charIndex in 0..<groupSize {
                result.append(characters[groupIndex * groupSize + charIndex])
            }
        }
        return result
    }
    
    
    enum ObvError: Error {
        case unexpectedError
    }
    
}


