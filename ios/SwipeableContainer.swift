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

protocol SwipeableContainerDelegate: AnyObject {
  func containerDidSwipeRight(_ container: SwipeableContainer)
  func containerDidSwipeLeft(_ container: SwipeableContainer)
  func containerDidSwipeUp(_ container: SwipeableContainer)
  func containerDidSwipeDown(_ container: SwipeableContainer)
}

class SwipeableContainer: UIView {
  weak var delegate: SwipeableContainerDelegate?

  // References to existing review UI elements
  private let questionLabel: UILabel
  private let gradientBackground: GradientView
  private var initialPanPoint: CGPoint = .zero
  private var currentSwipeDirection: SwipeDirection?
  private var originalGradientColors: [CGColor] = []

  // Configuration
  private let swipeThreshold: CGFloat = 100
  private let angleThreshold: CGFloat = .pi / 8 // 22.5 degrees for diagonal detection
  private let animationDuration: TimeInterval = 0.3

  init(questionLabel: UILabel, gradientBackground: GradientView) {
    self.questionLabel = questionLabel
    self.gradientBackground = gradientBackground
    super.init(frame: gradientBackground.bounds)
    setupGestureRecognizer()
    isUserInteractionEnabled = true
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  private func setupGestureRecognizer() {
    let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
    panGesture.delegate = self
    addGestureRecognizer(panGesture)
  }

  @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
    let translation = gesture.translation(in: self)
    let velocity = gesture.velocity(in: self)

    switch gesture.state {
    case .began:
      initialPanPoint = questionLabel.center
      currentSwipeDirection = nil
      originalGradientColors = gradientBackground.colors

    case .changed:
      let horizontalProgress = translation.x / swipeThreshold
      let verticalProgress = translation.y / swipeThreshold

      if currentSwipeDirection == nil {
        currentSwipeDirection = SwipeDirection.determineDirection(from: translation,
                                                                  angleThreshold: angleThreshold)
      }

      guard let direction = currentSwipeDirection else { return }

      var constrainedTranslation = translation
      var directionalProgress: CGFloat
      var tintColor: UIColor

      switch direction {
      case .left, .right:
        constrainedTranslation.y = 0
        tintColor = horizontalProgress > 0 ? UIColor.systemGreen : UIColor.systemRed
        directionalProgress = abs(horizontalProgress)

      case .up, .down:
        constrainedTranslation.x = 0
        tintColor = verticalProgress > 0 ? UIColor.systemBlue : UIColor.systemGray
        directionalProgress = abs(verticalProgress)
      }

      // move label
      questionLabel.center = CGPoint(x: initialPanPoint.x + constrainedTranslation.x,
                                     y: initialPanPoint.y + constrainedTranslation.y)

      // change tint color
      let originalColor = UIColor(cgColor: originalGradientColors[0])
      gradientBackground.colors[0] = UIColor.interpolate(from: originalColor, to: tintColor,
                                                         progress: directionalProgress).cgColor

    case .ended:
      handleSwipeEnd(translation: translation, velocity: velocity)

    default:
      resetViewPositions()
    }
  }

  private func handleSwipeEnd(translation: CGPoint, velocity: CGPoint) {
    let isHorizontalSwipe = abs(translation.x) > abs(translation.y)
    let isSignificantSwipe = isHorizontalSwipe ?
      (abs(translation.x) > swipeThreshold || abs(velocity.x) > 1000) :
      (abs(translation.y) > swipeThreshold || abs(velocity.y) > 1000)

    if isSignificantSwipe {
      let direction: SwipeDirection
      if isHorizontalSwipe {
        direction = translation.x > 0 ? .right : .left
      } else {
        direction = translation.y > 0 ? .down : .up
      }

      animateSwipeCompletion(in: direction)
    } else {
      resetViewPositions()
      resetGradientColors()
    }
  }

  private enum SwipeDirection {
    case left, right, up, down

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
      case -(.pi / 2 + angleThreshold) ... -(.pi / 2 - angleThreshold):
        return .up
      default:
        return nil
      }
    }

    var offset: CGPoint {
      switch self {
      case .left: return CGPoint(x: -1000, y: 0)
      case .right: return CGPoint(x: 1000, y: 0)
      case .up: return CGPoint(x: 0, y: -1000)
      case .down: return CGPoint(x: 0, y: 1000)
      }
    }
  }

  private func animateSwipeCompletion(in direction: SwipeDirection) {
    let offset = direction.offset

    UIView.animate(withDuration: animationDuration, animations: {
      self.questionLabel.center = CGPoint(x: self.initialPanPoint.x + offset.x,
                                          y: self.initialPanPoint.y + offset.y)
      self.questionLabel.alpha = 0
    }) { _ in
      // Notify delegate before showing next question
      switch direction {
      case .right: self.delegate?.containerDidSwipeRight(self)
      case .left: self.delegate?.containerDidSwipeLeft(self)
      case .up: self.delegate?.containerDidSwipeUp(self)
      case .down: self.delegate?.containerDidSwipeDown(self)
      }

      // Reset position without animation before making visible
      self.questionLabel.center = self.initialPanPoint

      // Make visible instantly
      self.questionLabel.alpha = 1
    }
  }

  private func resetViewPositions() {
    UIView.animate(withDuration: animationDuration) {
      self.questionLabel.center = self.initialPanPoint
      self.questionLabel.transform = .identity
    }
  }

  private func resetGradientColors() {
    gradientBackground
      .animateColors(to: originalGradientColors,
                     duration: 0.25) // TODO: duration should be kDefaultAnimation
  }
}

// MARK: - Extensions

extension SwipeableContainer: UIGestureRecognizerDelegate {
  func gestureRecognizer(_: UIGestureRecognizer,
                         shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer)
    -> Bool {
    // Allow tap gestures to work alongside pan
    otherGestureRecognizer is UITapGestureRecognizer
  }
}

extension UIColor {
  static func interpolate(from: UIColor, to: UIColor, progress: CGFloat) -> UIColor {
    let progress = min(1.0, max(0.0, progress)) // Clamp progress between 0 and 1
    var fRed: CGFloat = 0, fGreen: CGFloat = 0, fBlue: CGFloat = 0, fAlpha: CGFloat = 0
    var tRed: CGFloat = 0, tGreen: CGFloat = 0, tBlue: CGFloat = 0, tAlpha: CGFloat = 0

    from.getRed(&fRed, green: &fGreen, blue: &fBlue, alpha: &fAlpha)
    to.getRed(&tRed, green: &tGreen, blue: &tBlue, alpha: &tAlpha)

    return UIColor(red: fRed + (tRed - fRed) * progress,
                   green: fGreen + (tGreen - fGreen) * progress,
                   blue: fBlue + (tBlue - fBlue) * progress,
                   alpha: fAlpha + (tAlpha - fAlpha) * progress)
  }
}
