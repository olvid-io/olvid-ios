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
 *  You should have received a copy of the GNU Affero General Public License
 *  along with Olvid.  If not, see <https://www.gnu.org/licenses/>.
 */

import UIKit
import CoreData
import ObvUICoreData
import ObvLocation
import ObvUI
import ObvUIObvCircledInitials

protocol LocationViewDelegate: AnyObject {
    
    func locationViewUserWantsToOpenMapAt(latitude: Double, longitude: Double, locationView: LocationView)
    func locationViewUserWantsToStopSharingLocation(_ locationView: LocationView)
}

final class LocationView: ViewForOlvidStack, ViewWithMaskedCorners, ViewWithExpirationIndicator {
    
    struct Configuration: Equatable, Hashable {
        let latitude: Double?
        let longitude: Double?
        let address: String?
        let sharingType: PersistedLocation.ContinuousOrOneShot?
        let expirationDate: TimeInterval?
        let userCircledInitialsConfiguration: CircledInitialsConfiguration?
        let userCanStopSharingLocation: Bool
        let sentFromAnotherDevice: Bool
        let messageObjectID: TypeSafeManagedObjectID<PersistedMessage>?
        let snapshotFilename: String?
    }

    private var currentConfiguration: Configuration?
    
    func apply(_ newConfiguration: Configuration) {
        guard currentConfiguration != newConfiguration else { return }
        currentConfiguration = newConfiguration
        refresh()
    }
    
    var maskedCorner: UIRectCorner {
        get { bubble.maskedCorner }
        set {
            guard bubble.maskedCorner != newValue else { return }
            bubble.maskedCorner = newValue
        }
    }
    
    private let bubble = BubbleView()
    private let imageView = UIImageView()
    
    private let addressContainerView = UIView()
    private let addressEffectView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
    private let addressLabel = UILabel()
    
    // MARK: Attributes - Landmark Sharing
    private let pinpointContainerView = UIView()
    private let pinpointView = UIView()
    
    private let landmarkContainerView = MapLandmarkUIView()
    private let landmarkView = UIView()
    private let landmarkIconView = UIImageView()
    
    // MARK: Attributes - Continuous Sharing
    private let usermarkContainerView = UIView()
    private let usermarkImageView = NewCircledInitialsView()
    private let actionButton = UIButton()
    
    // MARK: Attributes - Stop Sharing
    private let stopSharingLabel = UILabel()
    private let stopUsermarkContainerView = UIView()
    private let stopUsermarkImageView = NewCircledInitialsView()
    private let stopUsermarkGradientView = LocationGradientView()
    
    // MARK: Attributes - Expiration View
    private let expirationLabel = UILabel()
    private let expirationImageView = UIImageView()
    private let expirationContainerView = UIView()
    
    
    let expirationIndicator = ExpirationIndicatorView()
    let expirationIndicatorSide: ExpirationIndicatorView.Side
    
    weak var delegate: LocationViewDelegate?
    
    init(expirationIndicatorSide side: ExpirationIndicatorView.Side) {
        self.expirationIndicatorSide = side
        super.init(frame: .zero)
        
        setupInternalViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private var messageSentFromCurrentDevice: Bool {
        guard let currentConfiguration else { return false }
        return currentConfiguration.userCanStopSharingLocation && !currentConfiguration.sentFromAnotherDevice
    }
    
    @objc private func actionButtonTapped(sender: UIButton) {
        if messageSentFromCurrentDevice {
            delegate?.locationViewUserWantsToStopSharingLocation(self)
        } else if let latitude = currentConfiguration?.latitude, let longitude = currentConfiguration?.longitude {
            delegate?.locationViewUserWantsToOpenMapAt(latitude: latitude, longitude: longitude, locationView: self)
        }
    }
    
    private func setupButtonAccordingly() {
        var configuration = actionButton.configuration
        if messageSentFromCurrentDevice {
            configuration?.title = Strings.stopSharingLocation
            configuration?.baseBackgroundColor = .red
        } else {
            configuration?.title = Strings.itinenary
            configuration?.baseBackgroundColor = UIColor(red: 79.0/255.0, green: 174.0/255.0, blue: 237.0/255.0, alpha: 1.0)
        }
        actionButton.configuration = configuration
        actionButton.isHidden = false
    }
    
    private func setupInternalViews() {
        addSubview(bubble)
        bubble.translatesAutoresizingMaskIntoConstraints = false
        
        bubble.backgroundColor = .systemFill
        
        addSubview(expirationIndicator)
        expirationIndicator.translatesAutoresizingMaskIntoConstraints = false
        
        bubble.addSubview(imageView)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.backgroundColor = .clear
        imageView.contentMode = .scaleAspectFill
        
        bubble.addSubview(addressContainerView)
        addressContainerView.translatesAutoresizingMaskIntoConstraints = false
        
        addressContainerView.addSubview(addressEffectView)
        addressEffectView.translatesAutoresizingMaskIntoConstraints = false
        
        addressContainerView.addSubview(addressLabel)
        addressLabel.font = UIFont.preferredFont(forTextStyle: .caption2)
        addressLabel.textColor = .secondaryLabel
        addressLabel.numberOfLines = 0
        addressLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // MARK: Landmark Sharing
        bubble.addSubview(pinpointContainerView)
        pinpointContainerView.backgroundColor = .white
        pinpointContainerView.translatesAutoresizingMaskIntoConstraints = false
        pinpointContainerView.layer.cornerRadius = 3.0
        pinpointContainerView.layer.shadowOpacity = 0.33
        pinpointContainerView.layer.shadowRadius = 2.0
        pinpointContainerView.layer.shadowOffset = .init(width: 0.0, height: 1.0)
        
        pinpointContainerView.addSubview(pinpointView)
        pinpointView.backgroundColor = .red
        pinpointView.translatesAutoresizingMaskIntoConstraints = false
        pinpointView.layer.cornerRadius = 2.0
        
        bubble.addSubview(landmarkContainerView)
        landmarkContainerView.backgroundColor = .white
        landmarkContainerView.translatesAutoresizingMaskIntoConstraints = false
        
        landmarkContainerView.addSubview(landmarkView)
        landmarkView.backgroundColor = .red
        landmarkView.layer.cornerRadius = 13.0
        landmarkView.translatesAutoresizingMaskIntoConstraints = false
        
        landmarkView.addSubview(landmarkIconView)
        let symbolConfiguration = UIImage.SymbolConfiguration(pointSize: 14.0, weight: .regular)
        landmarkIconView.image = UIImage(systemIcon: .mappin, withConfiguration: symbolConfiguration)
        landmarkIconView.contentMode = .center
        landmarkIconView.tintColor = .white
        landmarkIconView.translatesAutoresizingMaskIntoConstraints = false
        
        // MARK: Continuous Sharing
        bubble.addSubview(usermarkContainerView)
        usermarkContainerView.backgroundColor = .white
        usermarkContainerView.layer.cornerRadius = 15.0
        usermarkContainerView.layer.shadowOpacity = 0.33
        usermarkContainerView.layer.shadowRadius = 3.0
        usermarkContainerView.layer.shadowOffset = .init(width: 0.0, height: 3.0)
        
        usermarkContainerView.translatesAutoresizingMaskIntoConstraints = false
        
        usermarkContainerView.addSubview(usermarkImageView)
        usermarkImageView.backgroundColor = .secondarySystemBackground
        usermarkImageView.layer.cornerRadius = 13.0
        usermarkImageView.translatesAutoresizingMaskIntoConstraints = false
        
        // MARK: Expiration
        bubble.addSubview(expirationContainerView)
        expirationContainerView.translatesAutoresizingMaskIntoConstraints = false
        expirationContainerView.layer.cornerRadius = 12.0
        expirationContainerView.backgroundColor = UIColor(red: 240.0/255.0, green: 149.0/255.0, blue: 54.0/255.0, alpha: 1.0)
        
        expirationContainerView.addSubview(expirationImageView)
        expirationImageView.translatesAutoresizingMaskIntoConstraints = false
        expirationImageView.image = UIImage(systemIcon: .clock)
        expirationImageView.contentMode = .scaleAspectFit
        expirationImageView.tintColor = .white
        
        expirationContainerView.addSubview(expirationLabel)
        expirationLabel.translatesAutoresizingMaskIntoConstraints = false
        expirationLabel.text = ""
        expirationLabel.font = UIFont.preferredFont(forTextStyle: .caption2)
        expirationLabel.textColor = .white
        expirationLabel.numberOfLines = 1
        
        // MARK: Stop Sharing Button
        bubble.addSubview(actionButton)
        actionButton.setTitleColor(.white, for: .normal)
        actionButton.layer.cornerRadius = 10.0
        var configuration = UIButton.Configuration.filled()
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer({ incoming in
            var outgoing = incoming
            outgoing.font = UIFont.systemFont(ofSize: 12.0, weight: .semibold)
            return outgoing
        })
        configuration.title = Strings.stopSharingLocation
        configuration.baseBackgroundColor = .red
        configuration.contentInsets = .init(top: 0.0, leading: 35.0, bottom: 0.0, trailing: 35.0)
        actionButton.configuration = configuration
        actionButton.addTarget(self, action: #selector(actionButtonTapped), for: .touchUpInside)
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        
        // MARK: Stop Sharing
        bubble.addSubview(stopSharingLabel)
        stopSharingLabel.font = UIFont.preferredFont(forTextStyle: .body)
        stopSharingLabel.textColor = .secondaryLabel
        stopSharingLabel.numberOfLines = 0
        stopSharingLabel.textAlignment = .center
        stopSharingLabel.translatesAutoresizingMaskIntoConstraints = false
        
        bubble.addSubview(stopUsermarkGradientView)
        stopUsermarkGradientView.translatesAutoresizingMaskIntoConstraints = false
        
        bubble.addSubview(stopUsermarkContainerView)
        stopUsermarkContainerView.backgroundColor = .white
        stopUsermarkContainerView.layer.cornerRadius = 15.0
        stopUsermarkContainerView.translatesAutoresizingMaskIntoConstraints = false
        
        stopUsermarkContainerView.addSubview(stopUsermarkImageView)
        stopUsermarkImageView.backgroundColor = .secondarySystemBackground
        stopUsermarkImageView.layer.cornerRadius = 13.0
        stopUsermarkImageView.translatesAutoresizingMaskIntoConstraints = false
        
        let constraints = [
            bubble.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            bubble.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            bubble.topAnchor.constraint(equalTo: self.topAnchor),
            bubble.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: bubble.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: bubble.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: bubble.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bubble.bottomAnchor),
            addressContainerView.leadingAnchor.constraint(equalTo: bubble.leadingAnchor),
            addressContainerView.trailingAnchor.constraint(equalTo: bubble.trailingAnchor),
            addressContainerView.bottomAnchor.constraint(equalTo: bubble.bottomAnchor),
            addressLabel.leadingAnchor.constraint(equalTo: addressContainerView.leadingAnchor, constant: 8),
            addressLabel.trailingAnchor.constraint(equalTo: addressContainerView.trailingAnchor, constant: -8),
            addressLabel.topAnchor.constraint(equalTo: addressContainerView.topAnchor, constant: 8),
            addressLabel.bottomAnchor.constraint(equalTo: addressContainerView.bottomAnchor, constant: -8),
            addressEffectView.leadingAnchor.constraint(equalTo: addressContainerView.leadingAnchor),
            addressEffectView.trailingAnchor.constraint(equalTo: addressContainerView.trailingAnchor),
            addressEffectView.topAnchor.constraint(equalTo: addressContainerView.topAnchor),
            addressEffectView.bottomAnchor.constraint(equalTo: addressContainerView.bottomAnchor),
            pinpointContainerView.centerXAnchor.constraint(equalTo: bubble.centerXAnchor),
            pinpointContainerView.centerYAnchor.constraint(equalTo: bubble.centerYAnchor),
            pinpointContainerView.widthAnchor.constraint(equalToConstant:6.0),
            pinpointContainerView.heightAnchor.constraint(equalToConstant:6.0),
            pinpointView.leadingAnchor.constraint(equalTo: pinpointContainerView.leadingAnchor, constant: 1),
            pinpointView.trailingAnchor.constraint(equalTo: pinpointContainerView.trailingAnchor, constant: -1),
            pinpointView.topAnchor.constraint(equalTo: pinpointContainerView.topAnchor, constant: 1),
            pinpointView.bottomAnchor.constraint(equalTo: pinpointContainerView.bottomAnchor, constant: -1),
            landmarkContainerView.centerXAnchor.constraint(equalTo: bubble.centerXAnchor),
            landmarkContainerView.bottomAnchor.constraint(equalTo: pinpointContainerView.topAnchor, constant: 0.0),
            landmarkContainerView.widthAnchor.constraint(equalToConstant:30.0),
            landmarkContainerView.heightAnchor.constraint(equalToConstant:45.0),
            landmarkView.centerXAnchor.constraint(equalTo: landmarkContainerView.centerXAnchor),
            landmarkView.centerYAnchor.constraint(equalTo: landmarkContainerView.centerYAnchor),
            landmarkView.widthAnchor.constraint(equalToConstant:26.0),
            landmarkView.heightAnchor.constraint(equalToConstant:26.0),
            landmarkIconView.leadingAnchor.constraint(equalTo: landmarkView.leadingAnchor),
            landmarkIconView.trailingAnchor.constraint(equalTo: landmarkView.trailingAnchor),
            landmarkIconView.topAnchor.constraint(equalTo: landmarkView.topAnchor),
            landmarkIconView.bottomAnchor.constraint(equalTo: landmarkView.bottomAnchor),
            usermarkContainerView.centerXAnchor.constraint(equalTo: bubble.centerXAnchor),
            usermarkContainerView.centerYAnchor.constraint(equalTo: bubble.centerYAnchor),
            usermarkContainerView.widthAnchor.constraint(equalToConstant:30.0),
            usermarkContainerView.heightAnchor.constraint(equalToConstant:30.0),
            usermarkImageView.leadingAnchor.constraint(equalTo: usermarkContainerView.leadingAnchor, constant: 2),
            usermarkImageView.trailingAnchor.constraint(equalTo: usermarkContainerView.trailingAnchor, constant: -2),
            usermarkImageView.topAnchor.constraint(equalTo: usermarkContainerView.topAnchor, constant: 2),
            usermarkImageView.bottomAnchor.constraint(equalTo: usermarkContainerView.bottomAnchor, constant: -2),
            actionButton.bottomAnchor.constraint(equalTo: bubble.bottomAnchor, constant: -24),
            actionButton.centerXAnchor.constraint(equalTo: bubble.centerXAnchor),
            actionButton.heightAnchor.constraint(equalToConstant: 40.0),
            stopSharingLabel.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 24.0),
            stopSharingLabel.trailingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: -24.0),
            stopSharingLabel.centerYAnchor.constraint(equalTo: bubble.centerYAnchor, constant: 34.0),
            stopUsermarkGradientView.centerXAnchor.constraint(equalTo: stopUsermarkContainerView.centerXAnchor),
            stopUsermarkGradientView.centerYAnchor.constraint(equalTo: stopUsermarkContainerView.centerYAnchor),
            stopUsermarkGradientView.widthAnchor.constraint(equalToConstant: 60.0),
            stopUsermarkGradientView.heightAnchor.constraint(equalToConstant: 60.0),
            stopUsermarkContainerView.centerXAnchor.constraint(equalTo: bubble.centerXAnchor),
            stopUsermarkContainerView.bottomAnchor.constraint(equalTo: stopSharingLabel.topAnchor, constant: -24.0),
            stopUsermarkContainerView.widthAnchor.constraint(equalToConstant: 30.0),
            stopUsermarkContainerView.heightAnchor.constraint(equalToConstant: 30.0),
            stopUsermarkImageView.leadingAnchor.constraint(equalTo: stopUsermarkContainerView.leadingAnchor, constant: 2),
            stopUsermarkImageView.trailingAnchor.constraint(equalTo: stopUsermarkContainerView.trailingAnchor, constant: -2),
            stopUsermarkImageView.topAnchor.constraint(equalTo: stopUsermarkContainerView.topAnchor, constant: 2),
            stopUsermarkImageView.bottomAnchor.constraint(equalTo: stopUsermarkContainerView.bottomAnchor, constant: -2),
            expirationContainerView.topAnchor.constraint(equalTo: bubble.topAnchor, constant: 8.0),
            expirationContainerView.leadingAnchor.constraint(equalTo: bubble.leadingAnchor, constant: 8.0),
            expirationContainerView.heightAnchor.constraint(equalToConstant: 24.0),
            expirationImageView.topAnchor.constraint(equalTo: expirationContainerView.topAnchor, constant: 4.0),
            expirationImageView.leadingAnchor.constraint(equalTo: expirationContainerView.leadingAnchor, constant: 2.0),
            expirationImageView.bottomAnchor.constraint(equalTo: expirationContainerView.bottomAnchor, constant: -4.0),
            expirationLabel.topAnchor.constraint(equalTo: expirationContainerView.topAnchor, constant: 4.0),
            expirationLabel.trailingAnchor.constraint(equalTo: expirationContainerView.trailingAnchor, constant: -6.0),
            expirationLabel.bottomAnchor.constraint(equalTo: expirationContainerView.bottomAnchor, constant: -4.0),
            expirationLabel.leadingAnchor.constraint(equalTo: expirationImageView.trailingAnchor, constant: 0.0),
        ]
        
        constraints.forEach { $0.priority -= 1 }
        NSLayoutConstraint.activate(constraints)
        
        let sizeConstraints = [
            bubble.widthAnchor.constraint(equalToConstant: SingleImageView.imageSize),
            bubble.heightAnchor.constraint(equalToConstant: SingleImageView.imageSize),
        ]
        sizeConstraints.forEach { $0.priority -= 1 }
        NSLayoutConstraint.activate(sizeConstraints)
        
        setupConstraintsForExpirationIndicator(gap: MessageCellConstants.gapBetweenExpirationViewAndBubble)
    }
    
    private func clearSnapshot() {
        self.imageView.image = nil
        self.imageView.alpha = 0
    }
    
    private func refreshDisplayType() {
        switch currentConfiguration?.sharingType {
        case .oneShot:
            landmarkContainerView.isHidden = false
            pinpointContainerView.isHidden = false
            usermarkContainerView.isHidden = true
            stopSharingLabel.isHidden = true
            stopUsermarkContainerView.isHidden = true
            stopUsermarkGradientView.isHidden = true
        case .continuous:
            landmarkContainerView.isHidden = true
            pinpointContainerView.isHidden = true
            usermarkContainerView.isHidden = false
            stopSharingLabel.isHidden = true
            stopUsermarkContainerView.isHidden = true
            stopUsermarkGradientView.isHidden = true
        case nil:
            landmarkContainerView.isHidden = true
            pinpointContainerView.isHidden = true
            usermarkContainerView.isHidden = true
            stopSharingLabel.isHidden = false
            stopUsermarkContainerView.isHidden = false
            stopUsermarkGradientView.isHidden = false
        }
    }
    
    private func formatExpirationDate(with expirationDate: TimeInterval) -> String? {
        guard expirationDate >= Date().timeIntervalSince1970 else { return nil }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.hour, .minute]
        
        return formatter.string(from: Date(), to: Date(timeIntervalSince1970: expirationDate))
    }
    
    private func refresh() {
        
        refreshDisplayType()
        
        if currentConfiguration?.sharingType == nil {
            if currentConfiguration?.userCanStopSharingLocation ?? false { // Sent Message
                stopSharingLabel.text = Strings.LocationSharedStopped
                stopSharingLabel.textColor = UIColor(red: 73.0/255.0, green: 160.0/255.0, blue: 245.0/255.0, alpha: 1.0)
                bubble.backgroundColor = UIColor(red: 238.0/255.0, green: 248.0/255.0, blue: 253.0/255.0, alpha: 1.0)
            } else { // Received message
                stopSharingLabel.text = Strings.expiredLocation
                stopSharingLabel.textColor = .secondaryLabel
                bubble.backgroundColor = .tertiarySystemFill
            }
            // User Circled Initials
            if let initialsConfiguration = currentConfiguration?.userCircledInitialsConfiguration {
                stopUsermarkImageView.configure(with: initialsConfiguration)
                stopUsermarkImageView.isHidden = false
            } else {
                stopUsermarkImageView.isHidden = true
            }
        } else {
            // User Circled Initials
            if let initialsConfiguration = currentConfiguration?.userCircledInitialsConfiguration {
                usermarkImageView.configure(with: initialsConfiguration)
                usermarkImageView.isHidden = false
            } else {
                usermarkImageView.isHidden = true
            }
        }
        
        // Stop Sharing Button is displayed if it is in sharing state.
        if currentConfiguration?.sharingType == .continuous {
            setupButtonAccordingly()
        } else {
            actionButton.isHidden = true
        }
        
        if currentConfiguration?.sharingType == .continuous,
           let expirationDate = currentConfiguration?.expirationDate,
           let formattedDate = formatExpirationDate(with: expirationDate),
           currentConfiguration?.userCanStopSharingLocation ?? false {
            expirationLabel.text = formattedDate
            expirationContainerView.isHidden = false
        } else {
            expirationContainerView.isHidden = true
        }
        // Address
        if let address = currentConfiguration?.address {
            let formattedAddress = address.replacingOccurrences(of: ", ", with: "\n")
            addressLabel.text = formattedAddress
            addressContainerView.isHidden = false
        } else {
            addressContainerView.isHidden = true
        }
        
        // snapshot
        
        clearSnapshot()
        
        guard let latitude = currentConfiguration?.latitude, let longitude = currentConfiguration?.longitude else {
            return
        }
        
        guard let snapshotFilename = currentConfiguration?.snapshotFilename else {
            return
        }
        
        Task {
            do {
                let snapshot = try await ObvLocationService.requestSnapshot(latitude:latitude,
                                                                            longitude:longitude,
                                                                            filename: snapshotFilename)
                if snapshotFilename == currentConfiguration?.snapshotFilename {
                    self.imageView.image = snapshot
                    self.imageView.alpha = 1.0
                }
            } catch {
            }
        }
    }
}

//MARK: extension - UIViewWithTappableStuff
extension LocationView: UIViewWithTappableStuff {
    
    func tappedStuff(tapGestureRecognizer: UITapGestureRecognizer, acceptTapOutsideBounds: Bool) -> TappedStuffForCell? {
        guard !self.isHidden && self.showInStack else { return nil }
        guard self.bounds.contains(tapGestureRecognizer.location(in: self)) else { return nil }
        guard let latitude = currentConfiguration?.latitude, let longitude = currentConfiguration?.longitude, let messageObjectID = currentConfiguration?.messageObjectID else { return nil }
        
        if #available(iOS 17.0, *), currentConfiguration?.sharingType == .continuous {
            return .openMap(messageObjectID: messageObjectID)
        } else if currentConfiguration?.sharingType != nil { // we want to open external map for One Shot location OR Continuous Location only for prior iOS17.0 version. If it is `nil`, it means it stops sharing location and we do nothing.
            return .openExternalMapAt(latitude: latitude, longitude: longitude, address: currentConfiguration?.address)
        }
        
        return nil
    }
    
    
}

class LocationGradientView: UIView {
    
    private lazy var pulse: CAGradientLayer = {
        let gradientLayer = CAGradientLayer()
        gradientLayer.type = .radial
        gradientLayer.colors = [ UIColor(red: 167.0/255.0, green: 221.0/255.0, blue: 251.0/255.0, alpha: 0.22).cgColor,
                                 UIColor(red: 167.0/255.0, green: 221.0/255.0, blue: 251.0/255.0, alpha: 0.8).cgColor]
        gradientLayer.locations = [ 0, 0.95, 1]
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 1)
        layer.addSublayer(gradientLayer)
        return gradientLayer
    }()
    
    override func layoutSubviews() {
        super.layoutSubviews()
        pulse.frame = bounds
        pulse.cornerRadius = bounds.width / 2.0
    }
}

class MapLandmarkUIView: UIView {
    
    override init(frame: CGRect) {
        super.init(frame: frame)
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        let path = getBezierPath(rect: CGRect(origin: .zero,
                                              size: CGSize(width: bounds.maxX, height: bounds.maxY)))
        let shapeLayer = CAShapeLayer()
        shapeLayer.path = path.cgPath
        layer.mask = shapeLayer
        //
        //        let shadowLayer = CAShapeLayer()
        //        shadowLayer.name = "shadowLayer"
        //        shadowLayer.path = path.cgPath
        //        shadowLayer.shadowOpacity = 0.33
        //        shadowLayer.shadowRadius = 3.0
        //        shadowLayer.shadowOffset = .init(width: 0.0, height: 3.0)
        //        shadowLayer.frame = frame
        //        superview!.layer.insertSublayer(shadowLayer, below: layer)
    }
    
    private func getBezierPath(rect: CGRect) -> UIBezierPath {
        let path = UIBezierPath()
        
        let radius = rect.width / 2.0
        let arrowSize: CGFloat = 4.0
        let arrowOffset: CGFloat = 2.0
        let arrowBasePosX: CGFloat = rect.midY + radius - arrowOffset
        let arrowTopPosX: CGFloat = rect.midY + radius + arrowSize
        let arrowRoundedBezierValue: CGFloat = 3.0
        
        // Circle
        path.addArc(withCenter: CGPoint(x: rect.midX, y: rect.midY), radius: radius, startAngle: 0, endAngle: 2.0 * Double.pi, clockwise: true)
        path.close()
        
        // Arrow
        path.move(to: CGPoint(x: rect.midX, y: arrowTopPosX))
        
        path.addCurve(to: CGPoint(x: rect.midX - 8, y: arrowBasePosX),
                      controlPoint1: CGPoint(x: rect.midX - arrowRoundedBezierValue, y: arrowTopPosX),
                      controlPoint2: CGPoint(x: rect.midX - arrowRoundedBezierValue, y: arrowBasePosX))
        
        path.addLine(to: CGPoint(x: rect.midX + 8, y: arrowBasePosX))
        
        path.addCurve(to: CGPoint(x: rect.midX, y: arrowTopPosX),
                      controlPoint1: CGPoint(x: rect.midX + arrowRoundedBezierValue, y: arrowBasePosX),
                      controlPoint2: CGPoint(x: rect.midX + arrowRoundedBezierValue, y: arrowTopPosX))
        
        path.close()
        return path
    }
}

private extension LocationView {
    
    struct Strings {
        
        static let itinenary = NSLocalizedString("BUTTON_LOCATION_ITINERARY", comment: "")
        static let stopSharingLocation = NSLocalizedString("BUTTON_LOCATION_STOP_SHARING", comment: "")
        static let expiredLocation = NSLocalizedString("LOCATION_EXPIRED", comment: "")
        static let LocationSharedStopped = NSLocalizedString("LOCATION_SHARED_STOPPED", comment: "")
    }
    
}
