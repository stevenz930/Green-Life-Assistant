//
//  GarbageObjectDetectorService.swift
//  EA
//
//  Created by Steven Z on 2026/05/01.
//

import CoreML
import Vision
import CoreGraphics
import ImageIO

struct DetectedObject {
    let label: String
    let confidence: Float
    let boundingBox: CGRect
}

@Observable
final class GarbageObjectDetectorService {
    var confidenceThreshold: Float = 0.25
    var maximumDetections: Int = 8

    private let visionModel: VNCoreMLModel

    init() {
        do {
            let model = try GarbageObjectDetector(configuration: MLModelConfiguration())
            visionModel = try VNCoreMLModel(for: model.model)
        } catch {
            fatalError("Failed to load GarbageObjectDetector model: \(error)")
        }
    }

    func detect(pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation = .right) throws -> [DetectedObject] {
        let request = VNCoreMLRequest(model: visionModel)
        request.imageCropAndScaleOption = .scaleFill

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation)
        try handler.perform([request])

        let observations = (request.results as? [VNRecognizedObjectObservation]) ?? []
        let filtered = observations
            .compactMap { observation -> DetectedObject? in
                guard let topLabel = observation.labels.first else { return nil }
                guard topLabel.confidence >= confidenceThreshold else { return nil }

                return DetectedObject(
                    label: topLabel.identifier,
                    confidence: topLabel.confidence,
                    boundingBox: observation.boundingBox
                )
            }
            .sorted { $0.confidence > $1.confidence }

        return Array(filtered.prefix(maximumDetections))
    }
}
