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
 *  but WITHOUT ANY WARRANTY without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU Affero General Public License for more details.
 *
 *  You should have received a copy of the GNU Affero General Public License
 *  along with Olvid.  If not, see <https://www.gnu.org/licenses/>.
 */

import Foundation


class PrivateObjectWrapper<WrapperType: AnyObject, EncodedString: PrivateObjectWrappingStringRepresentable> {
    
    private var objectWrapper: ObjectContainer<WrapperType>

    
    var wrappedObject: WrapperType? {
        self.objectWrapper.object
    }

    
    init?(objectToWrap sourceObject: AnyObject, shouldRetainObject: Bool = false) {
        
        guard let sourceObject = sourceObject as? NSObject,
              let className = EncodedString.className.decodedString,
              sourceObject.className == className
        else { return nil }
        
        self.objectWrapper = .init(objectToWrap: sourceObject, shouldRetainObject: shouldRetainObject)
    }
    
    
}


// MARK: - PrivateObjectWrappingStringRepresentable


protocol PrivateObjectWrappingStringRepresentable: RawRepresentable where RawValue == String {
    var encodedString: String { get }
    var decodedString: String? { get }
    static var className: Self { get }
}


extension PrivateObjectWrappingStringRepresentable {
    
    var decodedString: String? {
        let encodedString = self.encodedString
        
        if let decodedString = decodedStringCache[encodedString] { return decodedString }
        
        guard let data = Data(base64Encoded: encodedString),
              let decodedString = String(data: data, encoding: .utf8) else { return nil }
        
        decodedStringCache[encodedString] = decodedString
        return decodedString
    }
}


fileprivate var decodedStringCache: Dictionary<String, String> = [:]


// MARK: - ObjectContainer

fileprivate class ObjectContainer<T> {
    
    private let shouldRetainObject: Bool
    
    private var retainedObject: AnyObject?
    
    @objc private weak var unretainedObject: AnyObject?
    
    private var objectRaw: AnyObject? { self.shouldRetainObject ? self.retainedObject : unretainedObject }
    
    fileprivate var object: T? { self.objectRaw as? T }
    
    fileprivate init(objectToWrap object: AnyObject?, shouldRetainObject: Bool) {
        if shouldRetainObject {
            self.retainedObject = object
        } else {
            self.unretainedObject = object
        }
        
        self.shouldRetainObject = shouldRetainObject
    }
}


// MARK: - Private utils

fileprivate extension NSObject {
    var className: String {
        return NSStringFromClass(type(of: self))
    }
}
