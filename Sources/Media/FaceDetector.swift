//
//  NewFaceDetector.swift
//  TelePresence
//
//  Created by Bingyi Zhu on 2020/10/09.
//  Copyright © 2020 Bingyi Zhu. All rights reserved.
//

import Foundation
import Vision
import UIKit
import AVKit


@available(iOS 11, *)
public class FaceDetector {
    
    // Vision requests
    private var detectionRequests: [VNDetectFaceRectanglesRequest]?
    private var trackingRequests: [VNTrackObjectRequest]?
    lazy var sequenceRequestHandler = VNSequenceRequestHandler()
    
    public var lastBoundingBox: CGRect = .zero
    
    init() {
        prepareVisionRequest()
    }
    
    func exifOrientationForDeviceOrientation(_ deviceOrientation: UIDeviceOrientation) -> CGImagePropertyOrientation {
        
        switch deviceOrientation {
        case .portraitUpsideDown:
            return .rightMirrored
            
        case .landscapeLeft:
            return .downMirrored
            
        case .landscapeRight:
            return .upMirrored
            
        default:
            return .leftMirrored
        }
    }
    
    func exifOrientationForCurrentDeviceOrientation() -> CGImagePropertyOrientation {
        return exifOrientationForDeviceOrientation(UIDevice.current.orientation)
    }
    
    /// - Tag: WriteCompletionHandler
    fileprivate func prepareVisionRequest() {
        
        //self.trackingRequests = []
        var requests = [VNTrackObjectRequest]()
        
        let faceDetectionRequest = VNDetectFaceRectanglesRequest(completionHandler: { (request, error) in
            
            if error != nil {
                print("FaceDetection error: \(String(describing: error)).")
            }
            
            guard let faceDetectionRequest = request as? VNDetectFaceRectanglesRequest,
                let results = faceDetectionRequest.results as? [VNFaceObservation] else {
                    return
            }
            DispatchQueue.main.async {
                // Add the observations to the tracking list
                for observation in results {
                    let faceTrackingRequest = VNTrackObjectRequest(detectedObjectObservation: observation)
                    requests.append(faceTrackingRequest)
                }
                self.trackingRequests = requests
            }
            
        })
        
        // Start with detection.  Find face, then track it.
        self.detectionRequests = [faceDetectionRequest]
        
        self.sequenceRequestHandler = VNSequenceRequestHandler()
    }
    
    
    public func detect(sampleBuffer: CMSampleBuffer) {
        
        var requestHandlerOptions: [VNImageOption: AnyObject] = [:]
        let cameraIntrinsicData = CMGetAttachment(sampleBuffer, key: kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, attachmentModeOut: nil)
        if cameraIntrinsicData != nil {
            requestHandlerOptions[VNImageOption.cameraIntrinsics] = cameraIntrinsicData
        }
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("Failed to obtain a CVPixelBuffer for the current output frame.")
            return
        }
        
        let exifOrientation = self.exifOrientationForCurrentDeviceOrientation()
        
        guard let requests = self.trackingRequests, !requests.isEmpty else {
            // No tracking object detected, so perform initial detection
            let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                                            orientation: exifOrientation,
                                                            options: requestHandlerOptions)
            
            do {
                guard let detectRequests = self.detectionRequests else {
                    return
                }
                try imageRequestHandler.perform(detectRequests)
            } catch let error as NSError {
                NSLog("Failed to perform FaceRectangleRequest: %@", error)
            }
            return
        }
        
        do {
            try self.sequenceRequestHandler.perform(requests,
                                                     on: pixelBuffer,
                                                     orientation: exifOrientation)
        } catch let error as NSError {
            NSLog("Failed to perform SequenceRequest: %@", error)
        }
        
        // Setup the next round of tracking.
        var newTrackingRequests = [VNTrackObjectRequest]()
        for trackingRequest in requests {
            
            guard let results = trackingRequest.results else {
                return
            }
            
            guard let observation = results[0] as? VNDetectedObjectObservation else {
                return
            }
            
            print("\(observation.boundingBox)")
            lastBoundingBox = observation.boundingBox
            
            if !trackingRequest.isLastFrame {
                if observation.confidence > 0.3 {
                    trackingRequest.inputObservation = observation
                } else {
                    trackingRequest.isLastFrame = true
                }
                newTrackingRequests.append(trackingRequest)
            }
        }
        self.trackingRequests = newTrackingRequests
        
        if newTrackingRequests.isEmpty {
            // Nothing to track, so abort.
            return
        }
        
        
        
//        // Perform face landmark tracking on detected faces.
//        var faceLandmarkRequests = [VNDetectFaceLandmarksRequest]()
//
//        // Perform landmark detection on tracked faces.
//        for trackingRequest in newTrackingRequests {
//
//            let faceLandmarksRequest = VNDetectFaceLandmarksRequest(completionHandler: { (request, error) in
//
//                if error != nil {
//                    print("FaceLandmarks error: \(String(describing: error)).")
//                }
//
//                guard let landmarksRequest = request as? VNDetectFaceLandmarksRequest,
//                    let results = landmarksRequest.results as? [VNFaceObservation] else {
//                        return
//                }
//
//
//
////                // Perform all UI updates (drawing) on the main queue, not the background queue on which this handler is being called.
////                DispatchQueue.main.async {
////                    self.drawFaceObservations(results)
////                }
//            })
//
//            guard let trackingResults = trackingRequest.results else {
//                return
//            }
//
//            guard let observation = trackingResults[0] as? VNDetectedObjectObservation else {
//                return
//            }
//            let faceObservation = VNFaceObservation(boundingBox: observation.boundingBox)
//            faceLandmarksRequest.inputFaceObservations = [faceObservation]
//
//            // Continue to track detected facial landmarks.
//            faceLandmarkRequests.append(faceLandmarksRequest)
//
//            let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
//                                                            orientation: exifOrientation,
//                                                            options: requestHandlerOptions)
//
//            do {
//                try imageRequestHandler.perform(faceLandmarkRequests)
//            } catch let error as NSError {
//                NSLog("Failed to perform FaceLandmarkRequest: %@", error)
//            }
//        }
    }
}


