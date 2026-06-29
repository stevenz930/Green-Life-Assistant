//
//  ScanView.swift
//  EA
//
//  Created by Steven Z on 2026/04/14.
//

import SwiftUI
import ARKit
import RealityKit
import Vision
import CoreImage

struct ScanView: View {
    var isSessionActive: Bool = true

    @State private var detector = GarbageObjectDetectorService()
    @State private var inRangeBoxes2D: [DetectionBox2D] = []
    @State private var displayCards: [DetectionCard] = []
    @State private var selectedDetectionID: UUID?
    @State private var lockedCardFrame: CGRect?
    @State private var arViewInstanceID = UUID()

    private let centerROIProportion: CGFloat = ARObjectDetectionCoordinator.centerROI.width

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ARObjectDetectionView(detector: detector, isActive: isSessionActive) { payload in
                    inRangeBoxes2D = payload.inRangeBoxes2D
                    updateDisplayCards(with: payload.inRangeBoxes2D)
                    syncSelectedCard(with: displayCards)
                }
                .id(arViewInstanceID)
                .onChange(of: isSessionActive) { _, isActive in
                    if isActive {
                        // Recreate ARView when returning to this tab to avoid frozen camera feed.
                        arViewInstanceID = UUID()
                    }
                }
                .ignoresSafeArea()

                ForEach(displayCards) { card in
                    let box = card.detection
                    let frame = frameForNormalizedRect(box.boundingBox, in: geo.size)
                    let isExpanded = selectedDetectionID == card.id
                    let cardInfo = WasteCardInfo.info(for: box.label)
                    let cardAnchorFrame = isExpanded ? (lockedCardFrame ?? frame) : frame

                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.green, lineWidth: 2)
                            .frame(width: frame.width, height: frame.height)

                        VStack(alignment: .leading, spacing: 8) {
                            Button {
                                if isExpanded {
                                    selectedDetectionID = nil
                                    lockedCardFrame = nil
                                } else {
                                    selectedDetectionID = card.id
                                    lockedCardFrame = frame
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(cardInfo.localizedCategoryName)
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                    Text("\(Int(box.confidence * 100))%")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.white.opacity(0.9))
                                }
                                .frame(maxWidth: 130, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(Color.black.opacity(0.72))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)

                            if isExpanded {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("材質：\(cardInfo.material)")
                                    Text("類別：\(cardInfo.localizedCategoryName) (\(cardInfo.detectorLabel))")
                                    Text("處理方式：\(cardInfo.handlingSteps)")
                                    Text(cardInfo.detailText)
                                }
                                .font(.caption2)
                                .foregroundStyle(.white)
                                .padding(10)
                                .frame(maxWidth: 220, alignment: .leading)
                                .background(Color.black.opacity(0.76))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                        .offset(x: 2, y: -6)
                    }
                    .position(x: cardAnchorFrame.midX, y: cardAnchorFrame.midY)
                }

                let roiWidth = geo.size.width * centerROIProportion
                let roiHeight = geo.size.height * centerROIProportion
                ROIOutsideMask(
                    holeRect: CGRect(
                        x: (geo.size.width - roiWidth) / 2,
                        y: (geo.size.height - roiHeight) / 2,
                        width: roiWidth,
                        height: roiHeight
                    ),
                    cornerRadius: 14
                )
                .fill(Color.black.opacity(0.35), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)

                CornerROIOverlay(cornerLength: 22, lineWidth: 4)
                    .stroke(Color.white.opacity(0.95), style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
                    .frame(width: roiWidth, height: roiHeight)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    .allowsHitTesting(false)

            }
            .ignoresSafeArea()
        }
    }

    private func syncSelectedCard(with cards: [DetectionCard]) {
        guard let selectedDetectionID else { return }
        if !cards.contains(where: { $0.id == selectedDetectionID }) {
            self.selectedDetectionID = nil
            self.lockedCardFrame = nil
        }
    }

    private func updateDisplayCards(with boxes: [DetectionBox2D]) {
        guard !boxes.isEmpty else {
            displayCards.removeAll()
            return
        }

        var remainingOldCards = displayCards
        var matched: [DetectionCard] = []

        for box in boxes {
            let bestMatch = remainingOldCards
                .enumerated()
                .filter { $0.element.detection.label == box.label }
                .max { lhs, rhs in
                    iou(lhs.element.detection.boundingBox, box.boundingBox) <
                        iou(rhs.element.detection.boundingBox, box.boundingBox)
                }

            if let (index, oldCard) = bestMatch, iou(oldCard.detection.boundingBox, box.boundingBox) > 0.18 {
                matched.append(DetectionCard(id: oldCard.id, detection: box))
                remainingOldCards.remove(at: index)
            } else {
                matched.append(DetectionCard(id: UUID(), detection: box))
            }
        }

        displayCards = matched
    }

    private func iou(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = a.intersection(b)
        guard !intersection.isNull else { return 0 }
        let intersectionArea = intersection.width * intersection.height
        let unionArea = (a.width * a.height) + (b.width * b.height) - intersectionArea
        guard unionArea > 0 else { return 0 }
        return intersectionArea / unionArea
    }

    private func frameForNormalizedRect(_ rect: CGRect, in size: CGSize) -> CGRect {
        let x = rect.minX * size.width
        let y = (1 - rect.maxY) * size.height
        let width = rect.width * size.width
        let height = rect.height * size.height
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

private struct DetectionCard: Identifiable {
    let id: UUID
    let detection: DetectionBox2D
}

private struct CornerROIOverlay: Shape {
    let cornerLength: CGFloat
    let lineWidth: CGFloat

    func path(in rect: CGRect) -> Path {
        let c = min(cornerLength, rect.width * 0.25, rect.height * 0.25)
        let inset = lineWidth * 0.5
        let minX = rect.minX + inset
        let minY = rect.minY + inset
        let maxX = rect.maxX - inset
        let maxY = rect.maxY - inset

        var p = Path()

        p.move(to: CGPoint(x: minX, y: minY + c))
        p.addLine(to: CGPoint(x: minX, y: minY))
        p.addLine(to: CGPoint(x: minX + c, y: minY))

        p.move(to: CGPoint(x: maxX - c, y: minY))
        p.addLine(to: CGPoint(x: maxX, y: minY))
        p.addLine(to: CGPoint(x: maxX, y: minY + c))

        p.move(to: CGPoint(x: minX, y: maxY - c))
        p.addLine(to: CGPoint(x: minX, y: maxY))
        p.addLine(to: CGPoint(x: minX + c, y: maxY))

        p.move(to: CGPoint(x: maxX - c, y: maxY))
        p.addLine(to: CGPoint(x: maxX, y: maxY))
        p.addLine(to: CGPoint(x: maxX, y: maxY - c))

        return p
    }
}

private struct ROIOutsideMask: Shape {
    let holeRect: CGRect
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addRect(rect)
        p.addRoundedRect(in: holeRect, cornerSize: CGSize(width: cornerRadius, height: cornerRadius))
        return p
    }
}

#Preview {
    ScanView()
}

struct LiveDetectionPayload {
    let objects: [DetectedObject]
    let inRangeObjects: [DetectedObject]
    let inRangeBoxes2D: [DetectionBox2D]
    let edgeRefineSuccessCount: Int
    let edgeRefineFallbackCount: Int
}

struct DetectionBox2D: Identifiable {
    let label: String
    let confidence: Float
    let boundingBox: CGRect

    var id: String {
        let x = Int((boundingBox.origin.x * 1000).rounded())
        let y = Int((boundingBox.origin.y * 1000).rounded())
        let w = Int((boundingBox.size.width * 1000).rounded())
        let h = Int((boundingBox.size.height * 1000).rounded())
        return "\(label)|\(x)|\(y)|\(w)|\(h)"
    }
}

private struct WasteCardInfo {
    let detectorLabel: String
    let localizedCategoryName: String
    let material: String
    let handlingSteps: String
    let detailText: String

    static func info(for label: String) -> WasteCardInfo {
        let key = label.lowercased()
        let base = mapping[key] ?? fallback
        let localizedCategory = localizedCategoryMapping[key] ?? label
        return WasteCardInfo(
            detectorLabel: label,
            localizedCategoryName: localizedCategory,
            material: base.material,
            handlingSteps: base.handlingSteps,
            detailText: base.detailText
        )
    }

    private static let fallback = WasteCardInfo(
        detectorLabel: "unknown",
        localizedCategoryName: "待確認回收類別",
        material: "Unknown",
        handlingSteps: "先清潔、瀝乾、分開不同材質",
        detailText: "未能精準匹配此物件，建議先按主要材質分類，並參考附近回收點接收規則。"
    )

    private static let localizedCategoryMapping: [String: String] = [
        "animal waste": "動物排泄物",
        "construction waste": "建築廢料",
        "garbage bag": "垃圾袋",
        "glass": "玻璃",
        "metal": "金屬",
        "organic": "有機物",
        "paper": "紙類",
        "plastic": "塑膠",
        "waste": "一般垃圾"
    ]

    private static let mapping: [String: WasteCardInfo] = [
        "animal waste": WasteCardInfo(
            detectorLabel: "Animal Waste",
            localizedCategoryName: "動物排泄物",
            material: "有機污染物",
            handlingSteps: "使用密封袋分裝，避免與可回收物混放",
            detailText: "動物排泄物通常不屬可回收物，請按一般垃圾或指定有機廢棄渠道處理。"
        ),
        "construction waste": WasteCardInfo(
            detectorLabel: "Construction Waste",
            localizedCategoryName: "建築廢料",
            material: "混合建材",
            handlingSteps: "按材質分堆（木材/金屬/石膏等），交由專門回收或清運",
            detailText: "建築廢料通常不應投入一般回收桶，需使用指定清運或回收渠道。"
        ),
        "garbage bag": WasteCardInfo(
            detectorLabel: "Garbage Bag",
            localizedCategoryName: "垃圾袋",
            material: "混合材質",
            handlingSteps: "先分類袋內物，再處理袋體",
            detailText: "垃圾袋常含污染物，若無法清潔且材質不明，建議按一般垃圾處理。"
        ),
        "glass": WasteCardInfo(
            detectorLabel: "Glass",
            localizedCategoryName: "玻璃",
            material: "玻璃",
            handlingSteps: "清洗、瀝乾、破損時先包裝邊緣",
            detailText: "乾淨玻璃可回收；破碎玻璃請先做好防割包裝再投放。"
        ),
        "metal": WasteCardInfo(
            detectorLabel: "Metal",
            localizedCategoryName: "金屬",
            material: "金屬",
            handlingSteps: "清洗、瀝乾，可行時壓扁",
            detailText: "金屬容器通常可回收，請避免殘留液體或食物污染。"
        ),
        "organic": WasteCardInfo(
            detectorLabel: "Organic",
            localizedCategoryName: "有機物",
            material: "有機物",
            handlingSteps: "瀝乾水分、獨立收集",
            detailText: "有機廢棄物建議走廚餘/堆肥渠道，避免與乾淨可回收物混放。"
        ),
        "plastic": WasteCardInfo(
            detectorLabel: "Plastic",
            localizedCategoryName: "塑膠",
            material: "塑膠",
            handlingSteps: "沖洗乾淨、壓扁、去除內容物",
            detailText: "常見塑膠容器可回收，但受污染或混材包裝可能需一般廢棄。"
        ),
        "paper": WasteCardInfo(
            detectorLabel: "Paper",
            localizedCategoryName: "紙類",
            material: "紙類",
            handlingSteps: "保持乾爽、攤平、移除膠帶",
            detailText: "油污紙與濕紙會降低回收品質，需先清潔再分類。"
        ),
        "waste": WasteCardInfo(
            detectorLabel: "waste",
            localizedCategoryName: "一般垃圾",
            material: "未知/混合",
            handlingSteps: "先嘗試分離可回收部分，其餘密封後棄置",
            detailText: "此類通常代表混合或不明廢棄物，建議先做二次分類再決定去向。"
        )
    ]
}

struct ContourFeatures {
    let hasValidContour: Bool
    let contourBoundingBox: CGRect
    let fillRatio: Float
    let aspectRatio: Float

    static let invalid = ContourFeatures(
        hasValidContour: false,
        contourBoundingBox: .zero,
        fillRatio: 0,
        aspectRatio: 1
    )
}

struct ContourRefineResult {
    let refinedObjects: [DetectedObject]
    let contourFeatures: [ContourFeatures]
    let successCount: Int
    let fallbackCount: Int
}

struct ARObjectDetectionView: UIViewRepresentable {
    typealias Coordinator = ARObjectDetectionCoordinator

    let detector: GarbageObjectDetectorService
    let isActive: Bool
    let onDetected: (LiveDetectionPayload) -> Void

    func makeCoordinator() -> ARObjectDetectionCoordinator {
        ARObjectDetectionCoordinator(detector: detector, onDetected: onDetected)
    }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        if isActive {
            context.coordinator.start(in: arView)
        }
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        if isActive {
            context.coordinator.start(in: uiView)
        } else {
            context.coordinator.stop()
        }
    }

    static func dismantleUIView(_ uiView: ARView, coordinator: ARObjectDetectionCoordinator) {
        coordinator.stop()
    }
}

final class ARObjectDetectionCoordinator: NSObject, ARSessionDelegate {
    static let centerROI = CGRect(x: 0.275, y: 0.275, width: 0.45, height: 0.45)

    private let detector: GarbageObjectDetectorService
    private let onDetected: (LiveDetectionPayload) -> Void
    private weak var arView: ARView?
    private let detectionQueue = DispatchQueue(label: "scan.arkit.detection.queue")
    private var isSessionRunning = false

    private var isProcessing = false
    private var lastInferenceTime = Date.distantPast
    private let minInferenceInterval: TimeInterval = 0.35
    private let mergeIoUThreshold: CGFloat = 0.35
    private let maxEdgeRefineDetections = 6
    private let refineDeltaLimit: CGFloat = 0.20
    private let minClampedBoxSize: CGFloat = 0.02

    init(detector: GarbageObjectDetectorService, onDetected: @escaping (LiveDetectionPayload) -> Void) {
        self.detector = detector
        self.onDetected = onDetected
    }

    func start(in arView: ARView) {
        if isSessionRunning, self.arView === arView {
            return
        }

        if let oldARView = self.arView, oldARView !== arView {
            oldARView.session.pause()
            oldARView.session.delegate = nil
        }

        self.arView = arView
        arView.session.delegate = self

        let config = ARWorldTrackingConfiguration()
        config.environmentTexturing = .automatic
        arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
        isSessionRunning = true
    }

    func stop() {
        arView?.session.pause()
        arView?.session.delegate = nil
        arView = nil
        isSessionRunning = false
        isProcessing = false
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard isSessionRunning else { return }
        let now = Date()
        guard !isProcessing, now.timeIntervalSince(lastInferenceTime) > minInferenceInterval else {
            return
        }

        isProcessing = true
        lastInferenceTime = now

        let pixelBuffer = frame.capturedImage
        detectionQueue.async { [weak self] in
            guard let self else { return }
            defer { self.isProcessing = false }

            let objects = (try? self.detector.detect(pixelBuffer: pixelBuffer)) ?? []
            let inRangeObjects = objects.compactMap(self.clampObjectToROI(_:))
            let mergedObjects = self.mergeOverlappingDetections(inRangeObjects).compactMap(self.clampObjectToROI(_:))
            let refineResult = self.refineDetectionsWithContours(mergedObjects, pixelBuffer: pixelBuffer)
            let clampedRefinedObjects = refineResult.refinedObjects.compactMap(self.clampObjectToROI(_:))
            let inRangeBoxes2D = clampedRefinedObjects.map {
                DetectionBox2D(label: $0.label, confidence: $0.confidence, boundingBox: $0.boundingBox)
            }

            DispatchQueue.main.async {
                guard self.isSessionRunning else { return }
                self.onDetected(
                    LiveDetectionPayload(
                        objects: objects,
                        inRangeObjects: inRangeObjects,
                        inRangeBoxes2D: inRangeBoxes2D,
                        edgeRefineSuccessCount: refineResult.successCount,
                        edgeRefineFallbackCount: refineResult.fallbackCount
                    )
                )
            }
        }
    }

    private func clampObjectToROI(_ object: DetectedObject) -> DetectedObject? {
        guard let clamped = clampToROI(object.boundingBox) else { return nil }
        return DetectedObject(label: object.label, confidence: object.confidence, boundingBox: clamped)
    }

    private func clampToROI(_ box: CGRect) -> CGRect? {
        let clamped = box.intersection(Self.centerROI)
        guard !clamped.isNull, clamped.width >= minClampedBoxSize, clamped.height >= minClampedBoxSize else {
            return nil
        }
        return clamped
    }

    private func mergeOverlappingDetections(_ objects: [DetectedObject]) -> [DetectedObject] {
        guard !objects.isEmpty else { return [] }

        var mergedByLabel: [DetectedObject] = []
        let grouped = Dictionary(grouping: objects, by: { $0.label })

        for (_, labelObjects) in grouped {
            var clusters: [[DetectedObject]] = []

            for object in labelObjects {
                var mergedIntoCluster = false
                for idx in clusters.indices {
                    if clusters[idx].contains(where: { iou($0.boundingBox, object.boundingBox) >= mergeIoUThreshold }) {
                        clusters[idx].append(object)
                        mergedIntoCluster = true
                        break
                    }
                }
                if !mergedIntoCluster {
                    clusters.append([object])
                }
            }

            for cluster in clusters {
                guard let first = cluster.first else { continue }
                let unionBox = cluster.dropFirst().reduce(first.boundingBox) { $0.union($1.boundingBox) }
                let maxConfidence = cluster.map(\.confidence).max() ?? first.confidence
                mergedByLabel.append(
                    DetectedObject(label: first.label, confidence: maxConfidence, boundingBox: unionBox)
                )
            }
        }

        return mergedByLabel
    }

    private func iou(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = a.intersection(b)
        guard !intersection.isNull else { return 0 }
        let intersectionArea = intersection.width * intersection.height
        let unionArea = (a.width * a.height) + (b.width * b.height) - intersectionArea
        guard unionArea > 0 else { return 0 }
        return intersectionArea / unionArea
    }

    private func refineDetectionsWithContours(
        _ objects: [DetectedObject],
        pixelBuffer: CVPixelBuffer
    ) -> ContourRefineResult {
        guard !objects.isEmpty else {
            return ContourRefineResult(refinedObjects: [], contourFeatures: [], successCount: 0, fallbackCount: 0)
        }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let imageSize = ciImage.extent.size
        let imageBounds = CGRect(origin: .zero, size: imageSize)
        let context = CIContext(options: nil)

        var refined: [DetectedObject] = []
        var features: [ContourFeatures] = []
        var successCount = 0
        var fallbackCount = 0

        for (index, object) in objects.enumerated() {
            if index >= maxEdgeRefineDetections {
                refined.append(object)
                features.append(.invalid)
                fallbackCount += 1
                continue
            }

            guard
                let roiRect = imageRect(fromNormalizedRect: object.boundingBox, imageSize: imageSize),
                let cgImage = context.createCGImage(ciImage, from: roiRect.intersection(imageBounds))
            else {
                refined.append(object)
                features.append(.invalid)
                fallbackCount += 1
                continue
            }

            let request = VNDetectContoursRequest()
            request.contrastAdjustment = 1.0
            request.detectsDarkOnLight = false
            request.maximumImageDimension = 256

            do {
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                try handler.perform([request])
                guard let observation = request.results?.first else {
                    refined.append(object)
                    features.append(.invalid)
                    fallbackCount += 1
                    continue
                }

                if let contourMetrics = contourMetrics(from: observation),
                   let normalized = normalizedRectFromContourBoundingBox(
                        contourMetrics.boundingBox,
                        roiInImage: roiRect,
                        imageSize: imageSize,
                        originalNormalized: object.boundingBox
                   ) {
                    refined.append(DetectedObject(label: object.label, confidence: object.confidence, boundingBox: normalized))
                    features.append(
                        ContourFeatures(
                            hasValidContour: true,
                            contourBoundingBox: contourMetrics.boundingBox,
                            fillRatio: contourMetrics.fillRatio,
                            aspectRatio: contourMetrics.aspectRatio
                        )
                    )
                    successCount += 1
                } else {
                    refined.append(object)
                    features.append(.invalid)
                    fallbackCount += 1
                }
            } catch {
                refined.append(object)
                features.append(.invalid)
                fallbackCount += 1
            }
        }

        return ContourRefineResult(
            refinedObjects: refined,
            contourFeatures: features,
            successCount: successCount,
            fallbackCount: fallbackCount
        )
    }

    private func imageRect(fromNormalizedRect rect: CGRect, imageSize: CGSize) -> CGRect? {
        guard imageSize.width > 0, imageSize.height > 0 else { return nil }
        let x = rect.minX * imageSize.width
        let y = (1.0 - rect.maxY) * imageSize.height
        let width = rect.width * imageSize.width
        let height = rect.height * imageSize.height
        let result = CGRect(x: x, y: y, width: width, height: height).integral
        return result.isNull || result.width < 2 || result.height < 2 ? nil : result
    }

    private func normalizedRectFromContourBoundingBox(
        _ contourRect: CGRect,
        roiInImage: CGRect,
        imageSize: CGSize,
        originalNormalized: CGRect
    ) -> CGRect? {
        let contourInImage = CGRect(
            x: roiInImage.minX + contourRect.minX * roiInImage.width,
            y: roiInImage.minY + contourRect.minY * roiInImage.height,
            width: contourRect.width * roiInImage.width,
            height: contourRect.height * roiInImage.height
        )
        guard contourInImage.width > 2, contourInImage.height > 2 else { return nil }

        var normalized = CGRect(
            x: contourInImage.minX / imageSize.width,
            y: 1.0 - (contourInImage.maxY / imageSize.height),
            width: contourInImage.width / imageSize.width,
            height: contourInImage.height / imageSize.height
        )

        let maxDx = originalNormalized.width * refineDeltaLimit
        let maxDy = originalNormalized.height * refineDeltaLimit
        let minW = originalNormalized.width * (1 - refineDeltaLimit)
        let maxW = originalNormalized.width * (1 + refineDeltaLimit)
        let minH = originalNormalized.height * (1 - refineDeltaLimit)
        let maxH = originalNormalized.height * (1 + refineDeltaLimit)

        normalized.origin.x = min(max(normalized.origin.x, originalNormalized.origin.x - maxDx), originalNormalized.origin.x + maxDx)
        normalized.origin.y = min(max(normalized.origin.y, originalNormalized.origin.y - maxDy), originalNormalized.origin.y + maxDy)
        normalized.size.width = min(max(normalized.size.width, minW), maxW)
        normalized.size.height = min(max(normalized.size.height, minH), maxH)

        let bounded = normalized.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        return bounded.isNull || bounded.width <= 0 || bounded.height <= 0 ? nil : bounded
    }

    private func contourMetrics(from observation: VNContoursObservation) -> (boundingBox: CGRect, fillRatio: Float, aspectRatio: Float)? {
        let topLevelContours = observation.topLevelContours
        guard !topLevelContours.isEmpty else {
            return nil
        }

        var unionRect = CGRect.null
        var stack = topLevelContours
        var contourArea: CGFloat = 0

        while let contour = stack.popLast() {
            let path = contour.normalizedPath
            let pathBounds = path.boundingBox
            unionRect = unionRect.isNull ? pathBounds : unionRect.union(pathBounds)
            contourArea += abs(path.signedArea)

            let children = contour.childContours
            if !children.isEmpty {
                stack.append(contentsOf: children)
            }
        }

        guard !unionRect.isNull, unionRect.width > 0, unionRect.height > 0 else {
            return nil
        }
        let standardized = unionRect.standardized
        let bboxArea = standardized.width * standardized.height
        guard bboxArea > 0 else { return nil }

        let fill = Float(min(max(contourArea / bboxArea, 0), 1))
        let ratio = Float(max(standardized.width, standardized.height) / max(min(standardized.width, standardized.height), 0.0001))
        return (standardized, fill, ratio)
    }
}

private extension CGPath {
    var signedArea: CGFloat {
        var area: CGFloat = 0
        var startPoint = CGPoint.zero
        var currentPoint = CGPoint.zero
        var hasSubpath = false

        self.applyWithBlock { elementPointer in
            let element = elementPointer.pointee
            switch element.type {
            case .moveToPoint:
                startPoint = element.points[0]
                currentPoint = startPoint
                hasSubpath = true
            case .addLineToPoint:
                let next = element.points[0]
                area += (currentPoint.x * next.y) - (next.x * currentPoint.y)
                currentPoint = next
            case .addQuadCurveToPoint:
                let next = element.points[1]
                area += (currentPoint.x * next.y) - (next.x * currentPoint.y)
                currentPoint = next
            case .addCurveToPoint:
                let next = element.points[2]
                area += (currentPoint.x * next.y) - (next.x * currentPoint.y)
                currentPoint = next
            case .closeSubpath:
                if hasSubpath {
                    area += (currentPoint.x * startPoint.y) - (startPoint.x * currentPoint.y)
                }
                hasSubpath = false
            @unknown default:
                break
            }
        }
        return area * 0.5
    }
}
