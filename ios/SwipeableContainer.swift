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

  private var initialPanPoint: CGPoint = .zero
  private var currentSwipeDirection: SwipeDirection?
  private var originalGradientColors: [CGColor] = []

  // Configuration
  private let swipeThreshold: CGFloat = 150
  private let angleThreshold: CGFloat = .pi / 8 // 22.5 degrees for diagonal detection
  private let kDefaultAnimationDuration: TimeInterval =
    0.25 // same as review view controller, maybe pass this around

  override init(frame: CGRect) {
    swipeConfiguration = .allDisabled
    leftBanner = UIView()
    rightBanner = UIView()

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

    leftBanner.isHidden = true
    rightBanner.isHidden = true

    updateBannerFrames()

    addSubview(leftBanner)
    addSubview(rightBanner)
  }

  private func updateBannerFrames() {
    leftBanner.frame = CGRect(x: -bounds.width, y: 0,
                              width: bounds.width, height: bounds.height)
    rightBanner.frame = CGRect(x: bounds.width, y: 0,
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

    static func determineDirection(from translation: CGPoint,
                                   angleThreshold: CGFloat) -> SwipeDirection? {
      let angle = atan2(translation.y, translation.x)

      switch angle {
      case -angleThreshold ... angleThreshold:
        return .right
      case (.pi - angleThreshold) ... .pi, -(.pi) ... -(.pi - angleThreshold):
        return .left
      case (.pi / 2 - angleThreshold) ... (.pi / 2 + angleThreshold):
        return .down
      default:
        return nil
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
                                                                              y: translation.y),
                                                                angleThreshold: angleThreshold)

      // Check if the determined direction is enabled
      guard let direction = currentSwipeDirection,
            isDirectionEnabled(direction) else {
        gesture.state = .cancelled
        return
      }

      leftBanner.isHidden = false
      rightBanner.isHidden = false

    case .changed:
      let progress = translation.x / swipeThreshold
      let clampedProgress = max(-1.0, min(1.0, progress))

      guard let direction = currentSwipeDirection,
            isDirectionEnabled(direction) else {
        return
      }

      // Animate banners
      UIView.animate(withDuration: 0.1) {
        if clampedProgress > 0 {
          self.leftBanner.frame.origin.x = -self.bounds.width + (translation.x)
          self.rightBanner.frame.origin.x = self.bounds.width
        } else {
          self.rightBanner.frame.origin.x = self.bounds.width + (translation.x)
          self.leftBanner.frame.origin.x = -self.bounds.width
        }
      }

    case .ended:
      let velocity = gesture.velocity(in: self)
      let isSignificant = abs(translation.x) > swipeThreshold || abs(velocity.x) > 1000

      if isSignificant, let direction = currentSwipeDirection, isDirectionEnabled(direction) {
        let direction: SwipeDirection = translation.x > 0 ? .right : .left
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
    let targetBanner = direction == .right ? leftBanner : rightBanner

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
        case .down: break
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
      // reset alpha after hiding to reduce flicker
      self.leftBanner.alpha = 1
      self.rightBanner.alpha = 1
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
