//
//  CALayer+Animation.swift
//  iTracker
//
//  Created by Kyle Krafka on 5/31/15.
//  Copyright (c) 2015 Kyle Krafka. All rights reserved.
//

import Foundation
import UIKit

/// Convenience functions to animate `CALayers`.
extension CALayer {
    func animateToPosition(newPosition: CGPoint) {
        let animation = CABasicAnimation(keyPath: "position")
        animation.fromValue = self.value(forKey: "position")
        animation.toValue = NSValue(cgPoint: newPosition)
        self.position = newPosition
        self.add(animation, forKey: "position")
    }
}
