/*
 *  Olvid for iOS
 *  Copyright © 2019-2021 Olvid SAS
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

class ObvCircledProgressView: UIView {

    static let nibName = "ObvCircledProgressView"

    private var spinner: UIActivityIndicatorView?
    
    var progressColor: UIColor = .darkGray {
        didSet {
            self.setNeedsDisplay()
        }
    }
    
    override var tintColor: UIColor! {
        didSet {
            imageView?.tintColor = self.tintColor
        }
    }
    
    
    @IBOutlet weak var imageView: UIImageView! {
        didSet {
            imageView?.tintColor = self.tintColor
            if let progress = observedProgress {
                updateImageViewDependingOnProgress(progress)
                self.setNeedsDisplay()
            }
        }
    }

    
    private let lineWidth: CGFloat = 5.0
    private let fullCircleColor = UIColor.lightGray
    private var progressObservationTokens = Set<NSKeyValueObservation>()
    private var previousFractionCompleted: Double = 0.0
    private var currentFractionCompleted: Double = 0.0
    private var progressBarShape: CAShapeLayer? = nil
    private var lastAnimationIsFinished = false
    private var progressWasDrawnAtLeastOnce = false
    
    
    var imageWhenPaused: UIImage? = nil {
        didSet {
            if let progress = observedProgress {
                updateImageViewDependingOnProgress(progress)
            }
        }
    }
    
    
    var imageWhenDownloading: UIImage? = nil {
        didSet {
            if let progress = observedProgress {
                updateImageViewDependingOnProgress(progress)
            }
        }
    }

    var imageWhenCancelled: UIImage? = nil {
        didSet {
            if let progress = observedProgress {
                updateImageViewDependingOnProgress(progress)
            }
        }
    }

    
    
    override func awakeFromNib() {
        super.awakeFromNib()
        translatesAutoresizingMaskIntoConstraints = false
    }
    
    
    private func updateImageViewDependingOnProgress(_ progress: Progress) {
        assert(Thread.current == Thread.main)
        if progress.isPausable {
            if progress.isPaused {
                self.imageView?.image = self.imageWhenPaused
            } else if progress.isCancelled {
                self.imageView?.image = self.imageWhenCancelled
                self.setNeedsDisplay()
            } else {
                self.imageView?.image = self.imageWhenDownloading
            }
        } else if progress.isCancelled {
            self.imageView?.image = self.imageWhenCancelled
            self.setNeedsDisplay()
        } else {
            self.imageView?.image = nil
        }
    }
    
    
    func showAsCancelled() {
        let fakeProgress = Progress()
        fakeProgress.cancel()
        self.observedProgress = fakeProgress
    }
    
    
    var observedProgress: Progress? {
        didSet {

            assert(Thread.current == Thread.main)
            
            if let progress = observedProgress {
                
                hideSpinner()
                
                previousFractionCompleted = progress.fractionCompleted
                currentFractionCompleted = progress.fractionCompleted
                
                do {
                    let token = progress.observe(\.fractionCompleted) { [weak self] (progress, _) in
                        debugPrint(progress.fractionCompleted)
                        guard let _self = self else { return }
                        DispatchQueue.main.async {
                            _self.previousFractionCompleted = _self.currentFractionCompleted
                            _self.currentFractionCompleted = progress.fractionCompleted
                            _self.hideSpinner()
                            _self.setNeedsDisplay()
                        }
                    }
                    self.progressObservationTokens.insert(token)
                }
                do {
                    let token = progress.observe(\.isPaused) { [weak self] (progress, _) in
                        guard let _self = self else { return }
                        DispatchQueue.main.async {
                            _self.hideSpinner()
                            _self.updateImageViewDependingOnProgress(progress)
                        }
                    }
                    self.progressObservationTokens.insert(token)
                }
                do {
                    let token = progress.observe(\.isCancelled) { [weak self] (progress, _) in
                        guard let _self = self else { return }
                        DispatchQueue.main.async {
                            _self.hideSpinner()
                            _self.updateImageViewDependingOnProgress(progress)
                        }
                    }
                    self.progressObservationTokens.insert(token)
                }
                
                updateImageViewDependingOnProgress(progress)

            } else {
                
                self.progressObservationTokens.removeAll()
                self.previousFractionCompleted = 0.0
                self.currentFractionCompleted = 0.0
                self.progressBarShape?.removeFromSuperlayer()
                self.progressBarShape = nil
                
                showSpinner()
                
            }
            
            lastAnimationIsFinished = false
            
            self.setNeedsDisplay()
        }
    }
    
    
    private func showSpinner() {
        assert(Thread.current == Thread.main)
        guard spinner == nil else { return }
        if #available(iOS 13.0, *) {
            spinner = UIActivityIndicatorView(style: .large)
            spinner!.translatesAutoresizingMaskIntoConstraints = false
            self.addSubview(spinner!)
            spinner!.pinAllSidesToSides(of: self)
            spinner!.hidesWhenStopped = true
            spinner!.startAnimating()
        } else {
            // Fallback on earlier versions
        }
    }
    
    private func hideSpinner() {
        assert(Thread.current == Thread.main)
        spinner?.stopAnimating()
        spinner?.removeFromSuperview()
        spinner = nil
    }
    
    override func draw(_ rect: CGRect) {
        
        guard observedProgress != nil else { return }
        guard !lastAnimationIsFinished else { return }
        guard observedProgress?.isCancelled == false else { return }
        
        // Draw the complete oval behind the progress
        
        let center = CGPoint(x: self.bounds.width/2, y: self.bounds.height/2)
        let progressBarPath = UIBezierPath(arcCenter: center,
                                           radius: self.bounds.width/2 - lineWidth / 2,
                                           startAngle: -CGFloat.pi / 2,
                                           endAngle: 3.0 * CGFloat.pi / 2.0,
                                           clockwise: true)
        fullCircleColor.setStroke()
        progressBarPath.lineWidth = lineWidth
        progressBarPath.stroke()

        if progressBarShape == nil {
            progressBarShape = generateProgressBarShape()
            progressBarShape!.frame = self.bounds
            self.layer.addSublayer(progressBarShape!)
        }

        // Animate the progress bar from the previous fraction completed up to the current fraction completed
        
        if currentFractionCompleted > previousFractionCompleted, let progressBarShape = self.progressBarShape {
            
            CATransaction.begin()
            CATransaction.setCompletionBlock { [weak self] in
                guard let _self = self else { return }
                if _self.observedProgress == nil || _self.observedProgress!.isFinished {
                    _self.progressBarShape?.removeAllAnimations()
                    _self.progressBarShape = nil
                    _self.lastAnimationIsFinished = true
                    _self.setNeedsDisplay()
                }
            }
            
            let animation = CABasicAnimation(keyPath: "strokeEnd")
            animation.toValue = CGFloat(currentFractionCompleted)
            animation.duration = 0.5
            animation.isRemovedOnCompletion = false
            animation.fillMode = .forwards
            
            progressBarShape.add(animation, forKey: nil)
            
            CATransaction.commit()
            
        } else if currentFractionCompleted > 0 && !progressWasDrawnAtLeastOnce {
            progressWasDrawnAtLeastOnce = true
            progressBarShape?.strokeEnd = CGFloat(currentFractionCompleted)
        }
        
    }
    
    private func generateProgressBarShape() -> CAShapeLayer {
        
        let shape = CAShapeLayer()
        
        let center = CGPoint(x: self.bounds.width/2, y: self.bounds.height/2)
        let progressBarPath = UIBezierPath(arcCenter: center,
                                           radius: self.bounds.width/2 - lineWidth / 2,
                                           startAngle: -CGFloat.pi / 2,
                                           endAngle: 3.0 * CGFloat.pi / 2.0,
                                           clockwise: true)
        shape.path = progressBarPath.cgPath
        shape.strokeColor = self.progressColor.cgColor
        shape.lineWidth = lineWidth
        shape.strokeStart = 0
        shape.strokeEnd = 0
        shape.lineCap = .round
        
        shape.fillColor = UIColor.clear.cgColor
        
        return shape
    }
}


// MARK: - Responding to tap

extension ObvCircledProgressView {
    
    @IBAction func tapPerformed(_ sender: UITapGestureRecognizer) {
        guard let progress = self.observedProgress else { return }
        guard progress.isPausable else { return }
        switch (progress.isPaused, progress.isCancelled) {
        case (false, false):
            progress.pause()
        case (false, true):
            progress.pause()
        case (true, false):
            progress.resume()
        case (true, true):
            progress.pause()
        }
    }
    
}
