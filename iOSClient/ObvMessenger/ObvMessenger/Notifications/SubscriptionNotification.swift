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
import StoreKit

fileprivate struct OptionalWrapper<T> {
	let value: T?
	public init() {
		self.value = nil
	}
	public init(_ value: T?) {
		self.value = value
	}
}

enum SubscriptionNotification {
	case newListOfSKProducts(result: Result<[SKProduct], SubscriptionCoordinator.RequestedListOfSKProductsError>)
	case userRequestedToBuySKProduct(skProduct: SKProduct)
	case skProductPurchaseFailed(error: SKError)
	case userRequestedListOfSKProducts
	case userDecidedToCancelToTheSKProductPurchase
	case skProductPurchaseWasDeferred
	case userRequestedToRestoreAppStorePurchases
	case thereWasNoAppStorePurchaseToRestore
	case allPurchaseTransactionsSentToEngineWereProcessed

	private enum Name {
		case newListOfSKProducts
		case userRequestedToBuySKProduct
		case skProductPurchaseFailed
		case userRequestedListOfSKProducts
		case userDecidedToCancelToTheSKProductPurchase
		case skProductPurchaseWasDeferred
		case userRequestedToRestoreAppStorePurchases
		case thereWasNoAppStorePurchaseToRestore
		case allPurchaseTransactionsSentToEngineWereProcessed

		private var namePrefix: String { String(describing: SubscriptionNotification.self) }

		private var nameSuffix: String { String(describing: self) }

		var name: NSNotification.Name {
			let name = [namePrefix, nameSuffix].joined(separator: ".")
			return NSNotification.Name(name)
		}

		static func forInternalNotification(_ notification: SubscriptionNotification) -> NSNotification.Name {
			switch notification {
			case .newListOfSKProducts: return Name.newListOfSKProducts.name
			case .userRequestedToBuySKProduct: return Name.userRequestedToBuySKProduct.name
			case .skProductPurchaseFailed: return Name.skProductPurchaseFailed.name
			case .userRequestedListOfSKProducts: return Name.userRequestedListOfSKProducts.name
			case .userDecidedToCancelToTheSKProductPurchase: return Name.userDecidedToCancelToTheSKProductPurchase.name
			case .skProductPurchaseWasDeferred: return Name.skProductPurchaseWasDeferred.name
			case .userRequestedToRestoreAppStorePurchases: return Name.userRequestedToRestoreAppStorePurchases.name
			case .thereWasNoAppStorePurchaseToRestore: return Name.thereWasNoAppStorePurchaseToRestore.name
			case .allPurchaseTransactionsSentToEngineWereProcessed: return Name.allPurchaseTransactionsSentToEngineWereProcessed.name
			}
		}
	}
	private var userInfo: [AnyHashable: Any]? {
		let info: [AnyHashable: Any]?
		switch self {
		case .newListOfSKProducts(result: let result):
			info = [
				"result": result,
			]
		case .userRequestedToBuySKProduct(skProduct: let skProduct):
			info = [
				"skProduct": skProduct,
			]
		case .skProductPurchaseFailed(error: let error):
			info = [
				"error": error,
			]
		case .userRequestedListOfSKProducts:
			info = nil
		case .userDecidedToCancelToTheSKProductPurchase:
			info = nil
		case .skProductPurchaseWasDeferred:
			info = nil
		case .userRequestedToRestoreAppStorePurchases:
			info = nil
		case .thereWasNoAppStorePurchaseToRestore:
			info = nil
		case .allPurchaseTransactionsSentToEngineWereProcessed:
			info = nil
		}
		return info
	}

	func post(object anObject: Any? = nil) {
		let name = Name.forInternalNotification(self)
		NotificationCenter.default.post(name: name, object: anObject, userInfo: userInfo)
	}

	func postOnDispatchQueue(object anObject: Any? = nil) {
		let name = Name.forInternalNotification(self)
		postOnDispatchQueue(withLabel: "Queue for posting \(name.rawValue) notification", object: anObject)
	}

	func postOnDispatchQueue(_ queue: DispatchQueue) {
		let name = Name.forInternalNotification(self)
		queue.async {
			NotificationCenter.default.post(name: name, object: nil, userInfo: userInfo)
		}
	}

	private func postOnDispatchQueue(withLabel label: String, object anObject: Any? = nil) {
		let name = Name.forInternalNotification(self)
		let userInfo = self.userInfo
		DispatchQueue(label: label).async {
			NotificationCenter.default.post(name: name, object: anObject, userInfo: userInfo)
		}
	}

	static func observeNewListOfSKProducts(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (Result<[SKProduct], SubscriptionCoordinator.RequestedListOfSKProductsError>) -> Void) -> NSObjectProtocol {
		let name = Name.newListOfSKProducts.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let result = notification.userInfo!["result"] as! Result<[SKProduct], SubscriptionCoordinator.RequestedListOfSKProductsError>
			block(result)
		}
	}

	static func observeUserRequestedToBuySKProduct(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (SKProduct) -> Void) -> NSObjectProtocol {
		let name = Name.userRequestedToBuySKProduct.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let skProduct = notification.userInfo!["skProduct"] as! SKProduct
			block(skProduct)
		}
	}

	static func observeSkProductPurchaseFailed(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping (SKError) -> Void) -> NSObjectProtocol {
		let name = Name.skProductPurchaseFailed.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			let error = notification.userInfo!["error"] as! SKError
			block(error)
		}
	}

	static func observeUserRequestedListOfSKProducts(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping () -> Void) -> NSObjectProtocol {
		let name = Name.userRequestedListOfSKProducts.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			block()
		}
	}

	static func observeUserDecidedToCancelToTheSKProductPurchase(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping () -> Void) -> NSObjectProtocol {
		let name = Name.userDecidedToCancelToTheSKProductPurchase.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			block()
		}
	}

	static func observeSkProductPurchaseWasDeferred(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping () -> Void) -> NSObjectProtocol {
		let name = Name.skProductPurchaseWasDeferred.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			block()
		}
	}

	static func observeUserRequestedToRestoreAppStorePurchases(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping () -> Void) -> NSObjectProtocol {
		let name = Name.userRequestedToRestoreAppStorePurchases.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			block()
		}
	}

	static func observeThereWasNoAppStorePurchaseToRestore(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping () -> Void) -> NSObjectProtocol {
		let name = Name.thereWasNoAppStorePurchaseToRestore.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			block()
		}
	}

	static func observeAllPurchaseTransactionsSentToEngineWereProcessed(object obj: Any? = nil, queue: OperationQueue? = nil, block: @escaping () -> Void) -> NSObjectProtocol {
		let name = Name.allPurchaseTransactionsSentToEngineWereProcessed.name
		return NotificationCenter.default.addObserver(forName: name, object: obj, queue: queue) { (notification) in
			block()
		}
	}

}
