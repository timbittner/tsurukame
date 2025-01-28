// Copyright 2025 David Sansome
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import UIKit

class SwipeableContainer: UIView {
  weak var delegate: SwipeableContainerDelegate?

  private(set) var swipeConfiguration: SwipeConfiguration

  private let leftBanner: UIView
  private let rightBanner: UIView
  private let topBanner: UIView

  private var initialPanPoint: CGPoint = .zero
  private var currentSwipeDirection: SwipeDirection?
  private var originalGradientColors: [CGColor] = []

  // Configuration
  private let swipeThreshold: CGFloat = 150 // around 3cm depending on device
  private let kDefaultAnimationDuration: TimeInterval =
    0.25 // same as review view controller, maybe pass this around

  override init(frame: CGRect) {
    swipeConfiguration = .allDisabled
    leftBanner = UIView()
    rightBanner = UIView()
    topBanner = UIView()

    super.init(frame: frame)

    setupBanners()
    setupGestureRecognizer()
    isUserInteractionEnabled = true
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setupBanners() {
    leftBanner.backgroundColor = TKMStyle.correctAnswerColor
    rightBanner.backgroundColor = TKMStyle.incorrectAnswerColor
    topBanner.backgroundColor = TKMStyle.Color.grey33

    leftBanner.isHidden = true
    rightBanner.isHidden = true
    topBanner.isHidden = true

    updateBannerFrames()

    addSubview(leftBanner)
    addSubview(rightBanner)
    addSubview(topBanner)

    // Add skip icon to top banner
    let skipIcon = UIImageView(image: Asset.goforwardPlus.image)
    skipIcon.tintColor = .white
    skipIcon.translatesAutoresizingMaskIntoConstraints = false
    topBanner.addSubview(skipIcon)

    NSLayoutConstraint.activate([
      skipIcon.centerXAnchor.constraint(equalTo: topBanner.centerXAnchor),
      skipIcon.bottomAnchor.constraint(equalTo: topBanner.bottomAnchor, constant: -48),
      skipIcon.widthAnchor.constraint(equalToConstant: 24),
      skipIcon.heightAnchor.constraint(equalToConstant: 24),
    ])
  }

  private func updateBannerFrames() {
    leftBanner.frame = CGRect(x: -bounds.width, y: 0,
                              width: bounds.width, height: bounds.height)
    rightBanner.frame = CGRect(x: bounds.width, y: 0,
                               width: bounds.width, height: bounds.height)
    topBanner.frame = CGRect(x: 0, y: -bounds.height,
                             width: bounds.width, height: bounds.height)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    updateBannerFrames()
  }

  private func setupGestureRecognizer() {
    let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
    panGesture.delegate = self
    addGestureRecognizer(panGesture)
  }

  // MARK: - Swipe Logic

  // Configuration for enabling/disabling swipe directions
  struct SwipeConfiguration {
    var isRightEnabled: Bool = false
    var isLeftEnabled: Bool = false
    var isDownEnabled: Bool = false

    static var allEnabled: SwipeConfiguration {
      SwipeConfiguration(isRightEnabled: true, isLeftEnabled: true, isDownEnabled: true)
    }

    static var allDisabled: SwipeConfiguration {
      SwipeConfiguration()
    }
  }

  private enum SwipeDirection {
    case left, right, down

    static func determineDirection(from translation: CGPoint) -> SwipeDirection? {
      // Use predominantly vertical/horizontal movement to determine direction
      let isVertical = abs(translation.y) > abs(translation.x)

      if isVertical {
        return translation.y > 0 ? .down : nil
      } else {
        return translation.x > 0 ? .right : .left
      }
    }
  }

  func updateSwipeConfiguration(_ configuration: SwipeConfiguration) {
    swipeConfiguration = configuration
  }

  private func isDirectionEnabled(_ direction: SwipeDirection) -> Bool {
    switch direction {
    case .right:
      return swipeConfiguration.isRightEnabled
    case .left:
      return swipeConfiguration.isLeftEnabled
    case .down:
      return swipeConfiguration.isDownEnabled
    }
  }

  @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
    let translation = gesture.translation(in: self)

    switch gesture.state {
    case .began:
      initialPanPoint = gesture.location(in: self)
      currentSwipeDirection = SwipeDirection.determineDirection(from: CGPoint(x: translation.x,
                                                                              y: translation.y))

      // Check if the determined direction is enabled
      guard let direction = currentSwipeDirection,
            isDirectionEnabled(direction) else {
        gesture.state = .cancelled
        return
      }

      leftBanner.isHidden = false
      rightBanner.isHidden = false
      topBanner.isHidden = false

    case .changed:

      guard let direction = currentSwipeDirection,
            isDirectionEnabled(direction) else {
        return
      }

      // Animate banners
      UIView.animate(withDuration: 0.1) {
        switch direction {
        case .down:
          let maxDistance = min(self.bounds.height, 150)
          let clampedTranslation = max(0, min(translation.y, maxDistance))
          self.topBanner.frame.origin.y = -self.bounds.height + clampedTranslation
        case .right:
          self.leftBanner.frame.origin.x = -self.bounds.width + (translation.x)
        case .left:
          self.rightBanner.frame.origin.x = self.bounds.width + (translation.x)
        }
      }

    case .ended:
      let velocity = gesture.velocity(in: self)
      guard let direction = currentSwipeDirection else {
        resetBanners()
        return
      }

      let isSignificant: Bool
      switch direction {
      case .down:
        // Only count velocity if still moving downward
        let hasDownwardVelocity = velocity.y > 0
        isSignificant = abs(translation.y) > min(bounds.height, swipeThreshold) ||
          (hasDownwardVelocity && abs(velocity.y) > 1000)
      case .left, .right:
        // Only count velocity if moving in original direction
        let isMovingRight = velocity.x > 0
        let matchesDirection = (direction == .right && isMovingRight) ||
          (direction == .left && !isMovingRight)
        isSignificant = abs(translation.x) > swipeThreshold ||
          (matchesDirection && abs(velocity.x) > 1000)
      }

      if isSignificant && isDirectionEnabled(direction) {
        animateSwipeCompletion(in: direction)
      } else {
        resetBanners()
      }

    default:
      resetBanners()
    }
  }

  // MARK: - Animation

  private func animateSwipeCompletion(in direction: SwipeDirection) {
    let targetBanner = direction == .right ? leftBanner :
      direction == .left ? rightBanner : topBanner

    UIView.animate(withDuration: kDefaultAnimationDuration, animations: {
      // First animation: fill screen
      targetBanner.frame = CGRect(x: 0, y: 0, width: self.bounds.width, height: self.bounds.height)

    }) { _ in
      // Second animation: Fade out banner
      UIView.animate(withDuration: self.kDefaultAnimationDuration,
                     delay: 0.1,
                     options: .curveEaseOut, animations: {
                       targetBanner.alpha = 0
                     }) { _ in
        // Notify delegate
        switch direction {
        case .right: self.delegate?.containerDidSwipeRight(self)
        case .left: self.delegate?.containerDidSwipeLeft(self)
        case .down: self.delegate?.containerDidSwipeDown(self)
        }

        self.resetBanners()
      }
    }
  }

  private func resetBanners() {
    // Slides the banners back to their original position and hides them
    UIView.animate(withDuration: kDefaultAnimationDuration, animations: {
      self.updateBannerFrames()
    }) { _ in
      self.leftBanner.isHidden = true
      self.rightBanner.isHidden = true
      self.topBanner.isHidden = true
      // reset alpha after hiding to reduce flicker
      self.leftBanner.alpha = 1
      self.rightBanner.alpha = 1
      self.topBanner.alpha = 1
    }
  }
}

// MARK: - Extensions and Protocols

extension SwipeableContainer: UIGestureRecognizerDelegate {
  func gestureRecognizer(_: UIGestureRecognizer,
                         shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer)
    -> Bool {
    // Allow tap gestures to work alongside pan
    otherGestureRecognizer is UITapGestureRecognizer
  }
}

protocol SwipeableContainerDelegate: AnyObject {
  func containerDidSwipeRight(_ container: SwipeableContainer)
  func containerDidSwipeLeft(_ container: SwipeableContainer)
  func containerDidSwipeDown(_ container: SwipeableContainer)
}
