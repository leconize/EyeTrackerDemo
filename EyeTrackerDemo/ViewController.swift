//
//  ViewController.swift
//  EyeTrackerDemo
//
//  Created by Harini Kannan on 2/18/16.
//  Copyright © 2016 Harini Kannan. All rights reserved.
//

///Users/harini/EyeTrackerDemo/EyeTrackerDemo/ViewController.swift
//  CameraViewController.swift
//  iTracker
//
//  Created by Kyle Krafka on 5/4/15.
//  Copyright (c) 2015 Kyle Krafka. All rights reserved.
//

import CoreGraphics
import CoreImage
import Foundation
import UIKit

/// Implements the view that shows camera output with boxes around the face and
/// eyes as well as an optional debug view to see the raw output of the eye
/// detectors.
class ViewController: UIViewController, EyeCaptureSessionDelegate {
    
    // MARK: Outlets.
    @IBOutlet weak var videoView: UIView!
    @IBOutlet weak var debugView: UIImageView!
    @IBOutlet weak var statusLabel: UILabel!
    @IBOutlet weak var detectorSegmentedControl: UISegmentedControl!
    @IBOutlet weak var rightEyeView: UIImageView!
    @IBOutlet weak var leftEyeView: UIImageView!
    // Boxes to display the most confident face.
    var faceLayer = CALayer()
    var leftEyeLayer = CALayer()
    var rightEyeLayer = CALayer()
    // Hide the boxes if they haven't been updated (i.e., their timer hasn't
    // been reset) recently enough.
    var faceTimeout: Timer?
    var leftEyeTimeout: Timer?
    var rightEyeTimeout: Timer?
    let timeoutLength = 0.2  // Number of seconds to leave a box on the screen after it's displayed.
    
    // Properties that will be initialized in viewDidLoad.
    var eyeCaptureSession: EyeCaptureSession!
    var statusTimer: Timer!

    var circleTimer: Timer?
    let redLayer = CALayer()
    let circleRadius = CGFloat(25)
    
    var newPosition: CGPoint?
    let neuralNet = NeuralNetwork()
    
    // From: http://iosdevcenters.blogspot.com/2015/12/how-to-resize-image-in-swift-in-ios.html
    func resizeImage(image: UIImage, targetSize: CGSize) -> UIImage {
        
        let rect = CGRect(x: 0, y: 0, width: targetSize.width, height: targetSize.height)
        
        // Actually do the resizing to the rect using the ImageContext stuff
        UIGraphicsBeginImageContextWithOptions(targetSize, false, 1.0)
        image.draw(in: rect)
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return newImage!
    }
    
    // MARK: - EyeCaptureSessionDelegate Methods
    func processFace(faceFrame ff: FaceFrame) {
        if leftEyeView.image != nil && rightEyeView.image != nil && ff.faceCrop != nil && ff.faceRect != nil {
            let size = CGSize(width: 219, height: 219)
            let resizedLeftEye = resizeImage(image: leftEyeView.image!, targetSize: size)
            let resizedRightEye = resizeImage(image: rightEyeView.image!, targetSize: size)
            let resizedFace = resizeImage(image: ff.faceCrop!, targetSize: size)
            
            let frameHeight = Double(Float(ff.fullFrameSize!.width))
            let frameWidth = Double(Float(ff.fullFrameSize!.height))
            
            let faceGridX = Double(Float(ff.faceRect!.origin.x))
            let faceGridY = Double(Float(ff.faceRect!.origin.y))
            let faceGridW = Double(Float(ff.faceRect!.size.width))
            let faceGridH = Double(Float(ff.faceRect!.size.height))
            let faceGrid:[Float] = createFaceGrid(frameW: frameWidth, frameH: frameHeight, gridW: 25.0, gridH: 25.0, labelFaceX: faceGridX, labelFaceY: faceGridY, labelFaceW: faceGridW, labelFaceH: faceGridH)
            
            let startTime = CFAbsoluteTimeGetCurrent()
            
            let output = self.neuralNet.run(faceGrid, firstImage: resizedLeftEye, secondImage: resizedRightEye, thirdImage: resizedFace)
            
            let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
            print("Run time: \(timeElapsed) s")
            
            let orientation = UIDevice.current.orientation.rawValue
            
            let frameSizePortrait = CGSize(width: min(view.frame.size.width, view.frame.size.height), height: max(view.frame.size.width, view.frame.size.height));

            var frameSize = frameSizePortrait
            
            if orientation == 3 || orientation == 4 {
                frameSize = CGSize(width: frameSizePortrait.height, height: frameSizePortrait.width)
            }
            
            convertCoords(xCam: Float(output.x), yCam: Float(output.y), deviceName: "iPhone 6s", labelOrientation: orientation, labelActiveScreenW: Int(frameSize.width), labelActiveScreenH: Int(frameSize.height), useCM: false)

        }

        if ff.faceCrop != nil && ff.faceRect != nil && ff.fullFrameSize != nil {
            if let videoPreviewLayer = self.eyeCaptureSession?.videoPreviewLayer {
                var faceRectDisp = ff.faceRect!
                
                faceRectDisp = faceRectDisp
                    .rectWithFlippedX(inFrame: ff.fullFrameSize!)  // TODO: Only do this if videoPreviewLayer.isMirrored
                
                // Orientation is corrected according to the device position in
                // EyeCaptureSession, but we don't rotate the UI here. This is
                // common in apps that actually display the camera, since
                // there's no need to rotate the main UI element (i.e., the
                // camera view. See the built-in Camera app (or really any
                // camera's UI) for an example.
                //
                // However, since the bounding box coordinates are relative to
                // the potentially-rotated raw image (so the head will be
                // upright and coordinates will be correct for that image), we
                // will un-rotate them here.
                
                // Rotate the frame so it's in portrait orientation (if it's not
                // already).
                var fullFrameSizePortrait = CGSize()
                if ff.deviceOrientation.isLandscape {
                    fullFrameSizePortrait = CGSize(width: ff.fullFrameSize!.height, height: ff.fullFrameSize!.width)
                } else {
                    // Could be portrait, portrait upside down, flat, or
                    // unknown. Regardless, we'll leave it as is.
                    fullFrameSizePortrait = ff.fullFrameSize!
                }
                // Now, update the coordinates of the face rect, in case the
                // frame was rotated.
                switch ff.deviceOrientation {
                case .portrait:
                    // Do nothing.
                    break
                case .landscapeLeft:
                    faceRectDisp = faceRectDisp
                        .rectRotatedRight(inSourceFrame: ff.fullFrameSize!)
                case .landscapeRight:
                    faceRectDisp = faceRectDisp
                        .rectRotatedLeft(inSourceFrame: ff.fullFrameSize!)
                case .portraitUpsideDown:
                    faceRectDisp = faceRectDisp
                        .rectRotated180(inSourceFrame: ff.fullFrameSize!)
                default:
                    fatalError("Unsupported orientation when displaying eye boxes.")
                }
                
                
                // The box in which the preview will show.
                // TODO: No need to recompute this every time.
                // TODO: Move this code to EyeCaptureSession since it owns the video
                //       preview layer.
                let videoPreviewBox = EyeCaptureSession.videoPreviewBoxForGravity(
                    gravity: videoPreviewLayer.videoGravity.rawValue,
                    viewSize: videoView.frame.size, imageSize: fullFrameSizePortrait)
                let scaleFactor = videoPreviewBox.width / fullFrameSizePortrait.width  // Could do height separately, but there are bigger problems if they're not the same scale.
                
                faceRectDisp = faceRectDisp.offsetBy(dx: -videoPreviewBox.origin.x, dy: -videoPreviewBox.origin.y)
                // These values were positive in Apple's SquareCam demo code.
                faceRectDisp = faceRectDisp.rectScaled(byFactor: scaleFactor)
                var leftEyeDisp, rightEyeDisp: CGRect?
                
                if let aLeftEye = ff.leftEye, let aRightEye = ff.rightEye {
                    // Mirror for display. Coordinates are already in UIKit space.
                    // TODO: Move the scaling stuff to the display method as well?
                    leftEyeDisp = aLeftEye
                        .rectScaled(byFactor: scaleFactor)
                        .rectWithFlippedX(inFrame: faceRectDisp)
                    rightEyeDisp = aRightEye
                        .rectScaled(byFactor: scaleFactor)
                        .rectWithFlippedX(inFrame: faceRectDisp)
                    switch ff.deviceOrientation {
                    case .portrait:
                        // Do nothing.
                        break
                    case .landscapeLeft:
                        leftEyeDisp = leftEyeDisp!
                            .rectRotatedRight(inSourceFrame: faceRectDisp)
                        rightEyeDisp = leftEyeDisp!
                            .rectRotatedRight(inSourceFrame: faceRectDisp)
                    case .landscapeRight:
                        leftEyeDisp = leftEyeDisp!
                            .rectRotatedLeft(inSourceFrame: faceRectDisp)
                        rightEyeDisp = rightEyeDisp!
                            .rectRotatedLeft(inSourceFrame: faceRectDisp)
                    case .portraitUpsideDown:
                        leftEyeDisp = leftEyeDisp!
                            .rectRotated180(inSourceFrame: faceRectDisp)
                        rightEyeDisp = rightEyeDisp!
                            .rectRotated180(inSourceFrame: faceRectDisp)
                    default:
                        fatalError("Unsupported orientation when displaying eye boxes.")
                    }
                }
                
                DispatchQueue.main.async {
                    self.drawBoxesForFace(face: faceRectDisp, faceYaw: ff.faceYaw,
                                          faceRoll: ff.faceRoll, leftEye: leftEyeDisp,
                                          leftEyeClosed: ff.leftEyeClosed, rightEye: rightEyeDisp,
                                          rightEyeClosed: ff.rightEyeClosed)
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    func updateStatus() {
        statusLabel.text = "FPS: \(self.eyeCaptureSession.frameFPS)  Detection: \(self.eyeCaptureSession.lastDetectionDuration) ms"
    }
    
    // Adapted from Kyle's cam2screen.m
    func convertCoords(xCam: Float, yCam: Float, deviceName: String, labelOrientation: Int, labelActiveScreenW: Int, labelActiveScreenH: Int, useCM: Bool){
        
        // First, convert input to millimeters to be compatible with AppleDeviceData.mat
        var xOut = xCam * 10
        var yOut = yCam * 10
        let deviceNames = ["iPhone 6s Plus", "iPhone 6s", "iPhone 6 Plus", "iPhone 6", "iPhone 5s", "iPhone 5c", "iPhone 5", "iPhone 4s", "iPad Mini", "iPad Air 2", "iPad Air", "iPad 4", "iPad 3", "iPad 2"]
        
        let deviceCameraToScreenXMm = [23.5400, 18.6100, 23.5400, 18.6100, 25.8500, 25.8500, 25.8500, 14.9600, 60.7000, 76.8600, 74.4000, 74.5000, 74.5000, 74.5000]
        let deviceCameraToScreenYMm = [8.6600, 8.0400, 8.6500, 8.0300, 10.6500, 10.6400, 10.6500, 9.7800, 8.7000, 7.3700, 9.9000, 10.5000, 10.5000, 10.5000]
        
        let deviceScreenWidthMm = [68.3600, 58.4900, 68.3600, 58.5000, 51.7000, 51.7000, 51.7000, 49.9200, 121.3000, 153.7100, 149.0000, 149.0000,149.0000, 149.0000]
        let deviceScreenHeightMm = [121.5400, 104.0500, 121.5400, 104.0500, 90.3900, 90.3900, 90.3900, 74.8800, 161.2000, 203.1100, 198.1000, 198.1000, 198.1000, 198.1000]
    
        var index = -1
        
        for i in 0..<deviceNames.count {
            if deviceNames[i] == deviceName {
                index = i
                break
            }
        }
//        for (var i=0; i < deviceNames.count; i++) {
//            if deviceNames[i] == deviceName {
//                index = i
//                break
//            }
//        }
        let dx = deviceCameraToScreenXMm[index]
        let dy = deviceCameraToScreenYMm[index]
        let dw = deviceScreenWidthMm[index]
        let dh = deviceScreenHeightMm[index]
        
        if labelOrientation == 1 {
            xOut = xOut + Float(dx)
            yOut = (-1)*(yOut) - Float(dy)
        } else if labelOrientation == 2 {
            xOut = xOut - Float(dx) + Float(dw)
            yOut = (-1)*(yOut) + Float(dy) + Float(dh)
        } else if labelOrientation == 3 {
            xOut = xOut - Float(dy)
            yOut = (-1)*(yOut) - Float(dx) + Float(dw)
        } else if labelOrientation == 4 {
            xOut = xOut + Float(dy) + Float(dh)
            yOut = (-1)*(yOut) + Float(dx)
        }
        
        if !useCM {
            if (labelOrientation == 1 || labelOrientation == 2) {
                xOut = (xOut * Float(labelActiveScreenW)) / Float(dw)
                yOut = (yOut * Float(labelActiveScreenH)) / Float(dh)
            } else if (labelOrientation == 3 || labelOrientation == 4) {
                xOut = (xOut * Float(labelActiveScreenW)) / Float(dh)
                yOut = (yOut * Float(labelActiveScreenH)) / Float(dw)
            }
        }
        
        if useCM {
            xOut = xOut / 10;
            yOut = yOut / 10;
        }
        
        let toPoint: CGPoint = CGPoint(x: CGFloat(xOut), y: CGFloat(yOut))
//        self.newPosition = toPoint
        
        let kalmanFilter = KalmanFilter()
        let smoothPoint = kalmanFilter?.processPoint(toPoint)
        self.newPosition = smoothPoint
        
        //print("Old point is (\(toPoint.x), \(toPoint.y)), and the new point is (\(smoothPoint.x), \(smoothPoint.y))")
        
        
    }
    
    // Adapted from Kyle's facerect2grid.m
    func createFaceGrid(frameW: Double, frameH: Double, gridW: Double, gridH: Double, labelFaceX: Double, labelFaceY: Double, labelFaceW: Double, labelFaceH: Double) -> Array<Float> {
        let scaleX = gridW / frameW
        let scaleY = gridH / frameH
        var grid = Array(repeating: Array(repeating: 0.0, count: Int(round(gridW))), count: Int(round(gridH)))
        var flattenedGrid = [Float](repeating: 0.0, count: 625)
        
        // Use zero-based image coordinates.
        var xLo = Int(round(labelFaceX * scaleX))
        var yLo = Int(round(labelFaceY * scaleY))
        let w = Int(round(labelFaceW * scaleX))
        let h = Int(round(labelFaceH * scaleY))
        var xHi = xLo + w - 1
        var yHi = yLo + h - 1
        xLo = min(Int(round(gridW) - 1), max(0, xLo))
        xHi = min(Int(round(gridW) - 1), max(0, xHi))
        yLo = min(Int(round(gridH) - 1), max(0, yLo))
        yHi = min(Int(round(gridH) - 1), max(0, yHi))
        
        for i in yLo..<yHi {
            for j in xLo..<xHi {
                flattenedGrid[25 * i + j] = 1.0
                grid[i][j] = 1.0
            }
        }
//        for var i=yLo; i < yHi + 1; i++ {
//            for var j=xLo; j < xHi+1; j++ {
//                flattenedGrid[25 * i + j] = 1.0
//                grid[i][j] = 1.0
//            }
//        }
        
        return flattenedGrid
    }
    
    // Draw three CGRects to the screen to display the eye detections. This must
    // be run on the main thread. All input values should be in the UIKit
    // coordinate space, with the origin at the top left.
    func drawBoxesForFace(face: CGRect, faceYaw: CGFloat?, faceRoll: CGFloat?,
        leftEye: CGRect?, leftEyeClosed: Bool?,
        rightEye: CGRect?, rightEyeClosed: Bool?) {
            CATransaction.begin()
            
            // Disable animations if the face layer was hidden. This is especially
            // good at the beginning to prevent black boxes from sliding out from
            // the origin. Alternatively, opacity alone could be animated.
        if faceLayer.isHidden {
                CATransaction.setValue(kCFBooleanTrue, forKey: kCATransactionDisableActions)
            }
            
            // Display a red box if the user is not looking directly at the camera.
            // Practically this only accepts values of 0.0 since yaw is currently
            // measured in increments of 45° and roll in increments of 30°.
        if (Double(faceYaw!) < 45.0 || Double(faceYaw!) > 315.0) && ( Double(faceRoll!) < 30.0 || Double(faceRoll!) > 330.0) {
                self.faceLayer.borderColor = UIColor.green.cgColor
            } else {
                self.faceLayer.borderColor = UIColor.red.cgColor
            }
            
            if leftEyeClosed == true {  // Explicitly testing == true also checks for nil appropriately.
                self.leftEyeLayer.borderColor = UIColor.red.cgColor
            } else {
                self.leftEyeLayer.borderColor = UIColor.green.cgColor
            }
            
            if rightEyeClosed == true {
                self.rightEyeLayer.borderColor = UIColor.red.cgColor
            } else {
                self.rightEyeLayer.borderColor = UIColor.green.cgColor
            }
            
        self.faceLayer.isHidden = false  // In case the box was hidden before, make sure it isn't now.
            self.faceLayer.frame = face   // Position the box.
            // Reset the timer so that the box disappears if not updated soon enough.
            if let oldFaceTimeout = self.faceTimeout {
                oldFaceTimeout.invalidate()
            }
        faceTimeout = Timer.scheduledTimer(timeInterval: self.timeoutLength, target: self, selector: Selector("hideFaceBox"), userInfo: nil, repeats: false)
            
            if let aLeftEye = leftEye {
                self.leftEyeLayer.isHidden = false
                self.leftEyeLayer.frame = aLeftEye
                if let oldLeftEyeTimeout = self.leftEyeTimeout {
                    oldLeftEyeTimeout.invalidate()
                }
                leftEyeTimeout = Timer.scheduledTimer(timeInterval: self.timeoutLength, target: self, selector: Selector("hideLeftEyeBox"), userInfo: nil, repeats: false)
            }
            
            if let aRightEye = rightEye {
                self.rightEyeLayer.isHidden = false
                self.rightEyeLayer.frame = aRightEye
                if let oldRightEyeTimeout = self.rightEyeTimeout {
                    oldRightEyeTimeout.invalidate()
                }
                rightEyeTimeout = Timer.scheduledTimer(timeInterval: self.timeoutLength, target: self, selector: Selector("hideRightEyeBox"), userInfo: nil, repeats: false)
            }
            CATransaction.commit()  // Done batching the UI updates together.
    }
    
    func hideFaceBox() {
        self.faceLayer.isHidden = true
        faceTimeout = nil
    }
    
    func hideLeftEyeBox() {
        self.leftEyeLayer.isHidden = true
        leftEyeTimeout = nil
    }
    
    func hideRightEyeBox() {
        self.rightEyeLayer.isHidden = true
        rightEyeTimeout = nil
    }
    
    // MARK: Actions
    
    @IBAction func didChangeDetector(sender: AnyObject) {
        switch self.detectorSegmentedControl.selectedSegmentIndex {
        case 0:
            self.eyeCaptureSession.selectedDetector = .CIDetector
        case 1:
            self.eyeCaptureSession.selectedDetector = .OpenCV
        default:
            print("Warning: Unrecognized index from detectorSegmentedControl. Defaulting to CIDetector.")
            self.eyeCaptureSession.selectedDetector = .CIDetector
        }
    }
    
    @IBAction func didTapVideoView(sender: AnyObject) {
        if self.eyeCaptureSession.debugView != nil {
            self.eyeCaptureSession.debugView = nil
            self.debugView.isHidden = true
            setup()
            print(self.leftEyeView.image!.size.height)
        } else {
            self.eyeCaptureSession.debugView = self.debugView
            self.debugView.isHidden = false
        }
    }
    
    // MARK: - View Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        //self.eyeCaptureSession.debugView = self.debugView
        self.debugView.isHidden = false
        faceLayer.borderWidth = 5
        leftEyeLayer.borderWidth = 3
        rightEyeLayer.borderWidth = 3
        faceLayer.isHidden = true
        leftEyeLayer.isHidden = true
        rightEyeLayer.isHidden = true
        videoView.layer.masksToBounds = true  // VERIFY: Should not be necessary, but prevent boxes from ever being drawn outside of the video layer.
        
        videoView.layer.insertSublayer(faceLayer, at: 0)
        // Eye boxes will be relative to the face.
        faceLayer.addSublayer(leftEyeLayer)
        faceLayer.addSublayer(rightEyeLayer)

        setup()

    }
    
    override func viewWillAppear(_ animated: Bool) {
        eyeCaptureSession = EyeCaptureSession(delegate: self, videoView: videoView, debugView: self.debugView, rightEyeView: self.rightEyeView, leftEyeView: self.leftEyeView)  // This will add the video layer to the very back, behind the face/eye boxes.
        
        // This default is set when declaring the variable, but we set it from
        // the segmented controller here just in case.
        didChangeDetector(sender: self.detectorSegmentedControl)
        statusTimer = Timer.scheduledTimer(timeInterval: 0.1, target: self, selector: Selector(("updateStatus")), userInfo: nil, repeats: true)
        
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        eyeCaptureSession = nil
        statusTimer.invalidate()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Scale the video output to the screen size.
        if let videoPreviewLayer = eyeCaptureSession?.videoPreviewLayer {  // We use ? because this function may be called after viewWillDisappear() is called.
            videoPreviewLayer.frame = videoView.layer.bounds
            videoPreviewLayer.position = CGPoint(x: videoView.layer.bounds.midX, y: videoView.layer.bounds.midY)
        }
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    func setup() {
        
//        let neuralNet = TestNtwkFile()
//        let startTime = CFAbsoluteTimeGetCurrent()
//        let output = neuralNet.testNtwkFile(nil, firstImage: nil, secondImage: nil, thirdImage: nil)
////        let output = TestNtwkFile.testNtwkFile(nil, firstImage: nil, secondImage: nil, thirdImage: nil)
//        let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime
//        print("Time elapsed for \(title): \(timeElapsed) s")
        redLayer.frame = CGRect(x: 100, y: 100, width: 50, height: 50)
        redLayer.backgroundColor = UIColor.red.cgColor
        
        // Round corners
        redLayer.cornerRadius = circleRadius
        
        // Set border
        redLayer.borderColor = UIColor.black.cgColor
        redLayer.borderWidth = 10
        
        redLayer.shadowColor = UIColor.black.cgColor
        redLayer.shadowOpacity = 0.8
        redLayer.shadowOffset = CGSize(width: 2, height: 2)
        redLayer.shadowRadius = 3
        
        self.videoView.layer.addSublayer(redLayer)
        
        circleTimer = Timer.scheduledTimer(timeInterval: 0.01, target: self, selector: Selector(("moveToPositionWithTimer")), userInfo: nil, repeats: true)
    }

    func moveToPositionWithTimer() {
        if self.newPosition != nil {
            self.redLayer.position = self.newPosition!
        } else {
            self.redLayer.position = CGPoint(x: 100,y: 100)
        }
    }
}


