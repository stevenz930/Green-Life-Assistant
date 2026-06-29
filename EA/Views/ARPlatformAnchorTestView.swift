//
//  ARPlatformAnchorTestView.swift
//  EA
//
//  Created by Steven Z on 2026/05/01.
//

import SwiftUI
import ARKit
import RealityKit
import Vision
import CoreImage
import ImageIO
import Photos

struct ARPlatformAnchorTestView: View {
    var isActive: Bool = true

    @State private var detector = GarbageObjectDetectorService()
    @State private var displayCards: [ARPlatformDetectionCard] = []
    @State private var selectedDetectionID: UUID?
    @State private var platformDetected = false
    @State private var isSavingPhoto = false
    @State private var captureRequestID: UUID?
    @State private var toast: ARPlatformInlineToast?
    @State private var arViewInstanceID = UUID()

    private let centerROIProportion: CGFloat = ARPlatformCameraCoordinator.centerROI.width

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ARPlatformCameraView(
                    detector: detector,
                    isActive: isActive,
                    selectedInfoCardContent: selectedInfoCardContent(),
                    captureRequestID: captureRequestID,
                    onCaptureCompleted: handlePhotoSaveResult(_:)
                ) { payload in
                    updateDisplayCards(with: payload.inRangeBoxes2D)
                    syncSelectedCard(with: displayCards)
                    platformDetected = payload.platformDetected
                }
                .id(arViewInstanceID)
                .onChange(of: isActive) { _, active in
                    if active {
                        arViewInstanceID = UUID()
                    }
                }
                .ignoresSafeArea()

                ForEach(displayCards) { card in
                    let box = card.detection
                    let frame = frameForNormalizedRect(box.boundingBox, in: geo.size)
                    let cardInfo = ARPlatformWasteCardInfo.info(for: box.label)

                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.green, lineWidth: 2)
                            .frame(width: frame.width, height: frame.height)

                        VStack(alignment: .leading, spacing: 8) {
                            Button {
                                if selectedDetectionID == card.id {
                                    selectedDetectionID = nil
                                } else {
                                    selectedDetectionID = card.id
                                }
                            } label: {
                                HStack{
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
                                    Spacer()
                                    Image(systemName: "arrowtriangle.right.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.white.opacity(0.9))
                                }
                                .frame(maxWidth: 130, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(Color.black.opacity(0.72))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }
                        .offset(x: 0, y: -50)
                    }
                    .position(x: frame.midX, y: frame.midY)
                }

                let roiWidth = geo.size.width * centerROIProportion
                let roiHeight = geo.size.height * centerROIProportion
                if !platformDetected {
                    ARPlatformROIOutsideMask(
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

                    ARPlatformCornerROIOverlay(cornerLength: 22, lineWidth: 4)
                        .stroke(
                            Color.white.opacity(0.95),
                            style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round)
                        )
                        .frame(width: roiWidth, height: roiHeight)
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                        .allowsHitTesting(false)
                }

                VStack(spacing: 12) {
                    if let toast {
                        Text(toast.message)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(toast.isSuccess ? Color.green.opacity(0.86) : Color.red.opacity(0.86))
                            .clipShape(Capsule())
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    Button(action: requestCameraFrameCapture) {
                        HStack(spacing: 8) {
                            if isSavingPhoto {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(.white)
                            } else {
                                Image(systemName: "camera.fill")
                            }
                            Text(isSavingPhoto ? "儲存中..." : "拍照並存相簿")
                                .fontWeight(.semibold)
                        }
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(Color.black.opacity(0.72))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isSavingPhoto)
                    .opacity(isSavingPhoto ? 0.75 : 1)
                }
                .padding(.bottom, 100)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
            .animation(.easeInOut(duration: 0.2), value: toast?.id)
            .ignoresSafeArea()
        }
    }

    private func syncSelectedCard(with cards: [ARPlatformDetectionCard]) {
        guard let selectedDetectionID else { return }
        if !cards.contains(where: { $0.id == selectedDetectionID }) {
            self.selectedDetectionID = nil
        }
    }

    private func updateDisplayCards(with boxes: [ARPlatformDetectionBox2D]) {
        guard !boxes.isEmpty else {
            displayCards.removeAll()
            return
        }

        // 透過 IoU 盡量沿用上一幀的卡片 ID，避免 UI 因為重建而閃爍。
        var remainingOldCards = displayCards
        var matched: [ARPlatformDetectionCard] = []

        for box in boxes {
            let bestMatch = remainingOldCards
                .enumerated()
                .filter { $0.element.detection.label == box.label }
                .max { lhs, rhs in
                    iou(lhs.element.detection.boundingBox, box.boundingBox) <
                        iou(rhs.element.detection.boundingBox, box.boundingBox)
                }

            if let (index, oldCard) = bestMatch, iou(oldCard.detection.boundingBox, box.boundingBox) > 0.18 {
                matched.append(ARPlatformDetectionCard(id: oldCard.id, detection: box))
                remainingOldCards.remove(at: index)
            } else {
                matched.append(ARPlatformDetectionCard(id: UUID(), detection: box))
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
        // Vision 的座標原點在左下；SwiftUI 畫面原點在左上，需做 Y 軸翻轉。
        let x = rect.minX * size.width
        let y = (1 - rect.maxY) * size.height
        let width = rect.width * size.width
        let height = rect.height * size.height
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func selectedInfoCardContent() -> ARPlatformARInfoCardContent? {
        guard let selectedDetectionID,
              let selectedCard = displayCards.first(where: { $0.id == selectedDetectionID }) else {
            return nil
        }
        let info = ARPlatformWasteCardInfo.info(for: selectedCard.detection.label)
        return ARPlatformARInfoCardContent(
            category: info.localizedCategoryName,
            material: info.material,
            handlingSteps: info.handlingSteps,
            detailText: info.detailText
        )
    }

    private func requestCameraFrameCapture() {
        guard !isSavingPhoto else { return }
        isSavingPhoto = true
        // Use request ID as a one-shot trigger into UIViewRepresentable/controller.
        captureRequestID = UUID()
    }

    private func handlePhotoSaveResult(_ result: ARPlatformPhotoSaveResult) {
        DispatchQueue.main.async {
            self.isSavingPhoto = false
            self.captureRequestID = nil

            switch result {
            case .success:
                self.showToast(message: "已儲存到相簿", isSuccess: true)
            case .failure(let message):
                self.showToast(message: message, isSuccess: false)
            }
        }
    }

    private func showToast(message: String, isSuccess: Bool) {
        let current = ARPlatformInlineToast(message: message, isSuccess: isSuccess)
        toast = current
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            if self.toast?.id == current.id {
                self.toast = nil
            }
        }
    }
}

private struct ARPlatformCameraView: UIViewControllerRepresentable {
    let detector: GarbageObjectDetectorService
    let isActive: Bool
    let selectedInfoCardContent: ARPlatformARInfoCardContent?
    let captureRequestID: UUID?
    let onCaptureCompleted: (ARPlatformPhotoSaveResult) -> Void
    let onDetected: (ARPlatformLiveDetectionPayload) -> Void

    func makeCoordinator() -> ARPlatformCameraCoordinator {
        ARPlatformCameraCoordinator(detector: detector, onDetected: onDetected)
    }

    func makeUIViewController(context: Context) -> ARPlatformCameraController {
        ARPlatformCameraController(coordinator: context.coordinator, isActive: isActive)
    }

    func updateUIViewController(_ uiViewController: ARPlatformCameraController, context: Context) {
        uiViewController.setSessionActive(isActive)
        uiViewController.setSelectedInfoCardContent(selectedInfoCardContent)
        uiViewController.setCaptureRequestID(captureRequestID, onCaptureCompleted: onCaptureCompleted)
    }
}

private final class ARPlatformCameraController: UIViewController {
    private let coordinator: ARPlatformCameraCoordinator
    private let arView = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
    private var desiredSessionActive: Bool
    private var isSessionActive = false

    init(coordinator: ARPlatformCameraCoordinator, isActive: Bool) {
        self.coordinator = coordinator
        self.desiredSessionActive = isActive
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        arView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(arView)
        NSLayoutConstraint.activate([
            arView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            arView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            arView.topAnchor.constraint(equalTo: view.topAnchor),
            arView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        setSessionActive(desiredSessionActive)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        setSessionActive(desiredSessionActive)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        setSessionActive(false)
    }

    func setSessionActive(_ isActive: Bool) {
        desiredSessionActive = isActive
        guard isViewLoaded else { return }
        guard isSessionActive != isActive else { return }

        isSessionActive = isActive
        if isActive {
            coordinator.start(in: arView)
        } else {
            coordinator.stop()
        }
    }

    func setSelectedInfoCardContent(_ content: ARPlatformARInfoCardContent?) {
        coordinator.setSelectedInfoCardContent(content)
    }

    func setCaptureRequestID(
        _ requestID: UUID?,
        onCaptureCompleted: @escaping (ARPlatformPhotoSaveResult) -> Void
    ) {
        coordinator.handleCaptureRequestID(requestID, onCaptureCompleted: onCaptureCompleted)
    }
}

private final class ARPlatformCameraCoordinator: NSObject {
    static let centerROI = CGRect(x: 0.275, y: 0.275, width: 0.45, height: 0.45)

    private struct ContourFeatures {
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

    private struct ContourRefineResult {
        let refinedObjects: [DetectedObject]
        let contourFeatures: [ContourFeatures]
        let successCount: Int
        let fallbackCount: Int
    }

    private let detector: GarbageObjectDetectorService
    private let onDetected: (ARPlatformLiveDetectionPayload) -> Void
    private weak var arView: ARView?

    private let detectionQueue = DispatchQueue(label: "arplatform.arkit.detection.queue")
    private var isSessionRunning = false
    private var isPreparingConfiguration = false
    private var startRequestID = UUID()
    private var isProcessing = false
    private var lastInferenceTime = Date.distantPast
    private let minInferenceInterval: TimeInterval = 0.35
    private let mergeIoUThreshold: CGFloat = 0.35
    private let maxEdgeRefineDetections = 6
    private let refineDeltaLimit: CGFloat = 0.20
    private let minClampedBoxSize: CGFloat = 0.02

    private var handledAnchorIDs = Set<UUID>()
    private var placedAnchorEntities = [UUID: AnchorEntity]()
    private var infoCardEntities = [UUID: Entity]()
    private var selectedInfoCardContent: ARPlatformARInfoCardContent?
    private var lastHandledCaptureRequestID: UUID?
    private var isCaptureInProgress = false
    private let photoProcessingQueue = DispatchQueue(label: "arplatform.photo.capture.queue")
    private let photoCIContext = CIContext(options: nil)
    private var lastPrintedCameraState: String?

    init(
        detector: GarbageObjectDetectorService,
        onDetected: @escaping (ARPlatformLiveDetectionPayload) -> Void
    ) {
        self.detector = detector
        self.onDetected = onDetected
    }

    func start(in arView: ARView) {
        let isSameView = (self.arView === arView)
        if let oldARView = self.arView, oldARView !== arView {
            // View 實例切換時先完整拆舊 session，避免 delegate/anchor 殘留。
            oldARView.session.pause()
            oldARView.session.delegate = nil
        }
        self.arView = arView
        arView.session.delegate = self

        guard !isSessionRunning || !isSameView else { return }
        guard !isPreparingConfiguration else { return }

        handledAnchorIDs.removeAll()
        placedAnchorEntities.values.forEach { $0.removeFromParent() }
        placedAnchorEntities.removeAll()
        arView.scene.anchors.removeAll()

        isPreparingConfiguration = true
        let requestID = UUID()
        startRequestID = requestID

        makeValidatedReferenceImage(
            fileName: "platform",
            anchorName: "platform",
            basePhysicalWidth: 0.2
        ) { [weak self] referenceImage in
            guard let self else { return }
            guard self.startRequestID == requestID else { return }
            self.isPreparingConfiguration = false

            guard let referenceImage else {
                print("Failed to create valid AR reference image from platform.png")
                return
            }

            self.runSession(with: [referenceImage], sourceLabel: "platform")
        }
    }

    func stop() {
        startRequestID = UUID()
        isPreparingConfiguration = false

        if let arView {
            arView.session.pause()
            arView.session.delegate = nil
            arView.scene.anchors.removeAll()
        }
        self.arView = nil

        handledAnchorIDs.removeAll()
        placedAnchorEntities.values.forEach { $0.removeFromParent() }
        placedAnchorEntities.removeAll()
        infoCardEntities.values.forEach { $0.removeFromParent() }
        infoCardEntities.removeAll()
        selectedInfoCardContent = nil
        lastHandledCaptureRequestID = nil
        isCaptureInProgress = false

        lastPrintedCameraState = nil
        isSessionRunning = false
        isProcessing = false

        onDetected(.empty)
    }

    func setSelectedInfoCardContent(_ content: ARPlatformARInfoCardContent?) {
        guard selectedInfoCardContent != content else { return }
        selectedInfoCardContent = content
        DispatchQueue.main.async {
            self.refreshInfoCardEntities()
        }
    }

    func handleCaptureRequestID(
        _ requestID: UUID?,
        onCaptureCompleted: @escaping (ARPlatformPhotoSaveResult) -> Void
    ) {
        guard let requestID else { return }
        // SwiftUI 可能重覆觸發同一個 requestID，這裡只處理一次。
        guard requestID != lastHandledCaptureRequestID else { return }
        lastHandledCaptureRequestID = requestID
        captureCameraFrameOnly(onCaptureCompleted: onCaptureCompleted)
    }

    private func runSession(with referenceImages: [ARReferenceImage], sourceLabel: String) {
        guard let arView else { return }
        guard let configuration = makeConfiguration(for: referenceImages) else { return }

        print("Tracking anchor source: \(sourceLabel)")
        arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        if let camera = arView.session.currentFrame?.camera {
            let state = cameraTrackingStateDescription(camera.trackingState)
            lastPrintedCameraState = state
            print("Camera tracking state: \(state)")
        } else {
            print("Camera tracking state: unavailable (no current frame yet)")
        }
        isSessionRunning = true
    }

    private func makeConfiguration(for referenceImages: [ARReferenceImage]) -> ARConfiguration? {
        let imageSet = Set(referenceImages)
        guard !imageSet.isEmpty else { return nil }

        if ARWorldTrackingConfiguration.isSupported {
            // 優先使用 WorldTracking，保留平面/姿態能力，影像偵測作為附加功能。
            let config = ARWorldTrackingConfiguration()
            config.detectionImages = imageSet
            config.maximumNumberOfTrackedImages = min(imageSet.count, 1)
            config.environmentTexturing = .automatic
            return config
        }

        if ARImageTrackingConfiguration.isSupported {
            // 次選 ImageTracking，裝置不支援 WorldTracking 時仍可做圖像錨點追蹤。
            let config = ARImageTrackingConfiguration()
            config.trackingImages = imageSet
            config.maximumNumberOfTrackedImages = min(imageSet.count, 1)
            return config
        }

        print("Neither image tracking nor world tracking is supported on this device")
        return nil
    }

    private func makeValidatedReferenceImage(
        fileName: String,
        anchorName: String,
        basePhysicalWidth: CGFloat,
        completion: @escaping (ARReferenceImage?) -> Void
    ) {
        guard let image = loadAnchorCGImage(named: fileName) else {
            print("\(fileName).png not found in app bundle")
            completion(nil)
            return
        }

        let candidates = makeReferenceImageCandidates(
            from: image,
            anchorName: anchorName,
            basePhysicalWidth: basePhysicalWidth
        )
        validateReferenceImageCandidate(candidates, index: 0, completion: completion)
    }

    private func loadAnchorCGImage(named fileName: String) -> CGImage? {
        guard let url = Bundle.main.url(forResource: fileName, withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }
        return image
    }

    private func makeReferenceImageCandidates(
        from cgImage: CGImage,
        anchorName: String,
        basePhysicalWidth: CGFloat
    ) -> [ARReferenceImage] {
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        guard width > 0, height > 0 else { return [] }

        let candidateRects: [CGRect] = [
            // 依序嘗試原圖、輕裁切、中度裁切，避開邊緣噪聲提升驗證成功率。
            CGRect(x: 0, y: 0, width: width, height: height),
            CGRect(x: width * 0.05, y: height * 0.05, width: width * 0.90, height: height * 0.90),
            CGRect(x: width * 0.10, y: height * 0.10, width: width * 0.80, height: height * 0.80)
        ]

        var results: [ARReferenceImage] = []
        for rect in candidateRects {
            let integralRect = CGRect(
                x: rect.origin.x.rounded(.down),
                y: rect.origin.y.rounded(.down),
                width: rect.size.width.rounded(.down),
                height: rect.size.height.rounded(.down)
            )
            guard integralRect.width > 0,
                  integralRect.height > 0,
                  let croppedImage = cgImage.cropping(to: integralRect) else {
                continue
            }

            let ratio = integralRect.width / width
            // 依裁切比例同步縮放實體寬度，避免 ARKit 尺度估計失真。
            let physicalWidth = max(basePhysicalWidth * ratio, 0.01)
            let referenceImage = ARReferenceImage(croppedImage, orientation: .up, physicalWidth: physicalWidth)
            referenceImage.name = anchorName
            results.append(referenceImage)
        }
        return results
    }

    private func validateReferenceImageCandidate(
        _ candidates: [ARReferenceImage],
        index: Int,
        completion: @escaping (ARReferenceImage?) -> Void
    ) {
        guard index < candidates.count else {
            completion(nil)
            return
        }

        let candidate = candidates[index]
        candidate.validate { error in
            DispatchQueue.main.async {
                if error != nil {
                    // 目前候選不合法就遞迴嘗試下一個，直到用完候選清單。
                    self.validateReferenceImageCandidate(candidates, index: index + 1, completion: completion)
                } else {
                    completion(candidate)
                }
            }
        }
    }

    private func clampObjectToROI(_ object: DetectedObject) -> DetectedObject? {
        guard let clamped = clampToROI(object.boundingBox) else { return nil }
        return DetectedObject(label: object.label, confidence: object.confidence, boundingBox: clamped)
    }

    private func clampToROI(_ box: CGRect) -> CGRect? {
        let clamped = box.intersection(Self.centerROI)
        // 過小框通常是抖動/誤檢，先在 ROI 階段濾掉可減少 UI 雜訊。
        guard !clamped.isNull, clamped.width >= minClampedBoxSize, clamped.height >= minClampedBoxSize else {
            return nil
        }
        return clamped
    }

    private func mergeOverlappingDetections(_ objects: [DetectedObject]) -> [DetectedObject] {
        guard !objects.isEmpty else { return [] }

        var mergedByLabel: [DetectedObject] = []
        // 不同類別不合併，避免把近距離的異類物件合成同一框。
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
                    refined.append(
                        DetectedObject(
                            label: object.label,
                            confidence: object.confidence,
                            boundingBox: normalized
                        )
                    )
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

        normalized.origin.x = min(
            max(normalized.origin.x, originalNormalized.origin.x - maxDx),
            originalNormalized.origin.x + maxDx
        )
        normalized.origin.y = min(
            max(normalized.origin.y, originalNormalized.origin.y - maxDy),
            originalNormalized.origin.y + maxDy
        )
        normalized.size.width = min(max(normalized.size.width, minW), maxW)
        normalized.size.height = min(max(normalized.size.height, minH), maxH)

        // 最終強制限制在 [0,1] 規範化座標，避免越界框造成繪製問題。
        let bounded = normalized.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        return bounded.isNull || bounded.width <= 0 || bounded.height <= 0 ? nil : bounded
    }

    private func contourMetrics(
        from observation: VNContoursObservation
    ) -> (boundingBox: CGRect, fillRatio: Float, aspectRatio: Float)? {
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
            contourArea += abs(signedArea(of: path))

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
        let ratio = Float(
            max(standardized.width, standardized.height) /
                max(min(standardized.width, standardized.height), 0.0001)
        )
        return (standardized, fill, ratio)
    }

    private func signedArea(of path: CGPath) -> CGFloat {
        var area: CGFloat = 0
        var startPoint = CGPoint.zero
        var currentPoint = CGPoint.zero
        var hasSubpath = false

        path.applyWithBlock { elementPointer in
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

    private func refreshInfoCardEntities() {
        for anchorID in placedAnchorEntities.keys {
            updateInfoCardEntity(for: anchorID)
        }
    }

    private func updateInfoCardEntity(for anchorID: UUID) {
        guard let anchorEntity = placedAnchorEntities[anchorID] else { return }

        // 先移除舊卡片再建新卡片，避免同一錨點重複疊加多張資訊面板。
        if let currentCard = infoCardEntities[anchorID] {
            currentCard.removeFromParent()
            infoCardEntities.removeValue(forKey: anchorID)
        }

        guard let selectedInfoCardContent else { return }
        let cardEntity = makeInfoCardEntity(from: selectedInfoCardContent)
        anchorEntity.addChild(cardEntity)
        infoCardEntities[anchorID] = cardEntity
    }

    private func makeInfoCardEntity(from content: ARPlatformARInfoCardContent) -> Entity {
        let root = Entity()
        root.position = SIMD3<Float>(0, 0.09, 0)
        root.orientation = simd_quatf(angle: 0, axis: SIMD3<Float>(1, 0, 0))

        let cardWidth: Float = 0.24
        let cardHeight: Float = 0.14
        let panelMesh = MeshResource.generatePlane(width: cardWidth, depth: cardHeight)
        let panelMaterial = SimpleMaterial(color: UIColor.black.withAlphaComponent(0.80), isMetallic: false)
        let panelEntity = ModelEntity(mesh: panelMesh, materials: [panelMaterial])
        panelEntity.position = SIMD3<Float>(0, 0, 0)
        root.addChild(panelEntity)

        let lines = [
            "類別: \(content.category)",
            "材質: \(content.material)",
            "處理: \(content.handlingSteps)",
            content.detailText
        ]

        let textMaterial = SimpleMaterial(color: .white, isMetallic: false)
        let clippedLines = lines.map { line in
            // 3D 文字排版成本高，先做字數裁切避免超出面板。
            if line.count > 22 {
                return String(line.prefix(21)) + "…"
            }
            return line
        }
        let blockText = clippedLines.joined(separator: "\n")

        let mesh = MeshResource.generateText(
            blockText,
            extrusionDepth: 0.0008,
            font: .systemFont(ofSize: 0.010, weight: .semibold),
            containerFrame: .zero,
            alignment: .left,
            lineBreakMode: .byWordWrapping
        )
        let textEntity = ModelEntity(mesh: mesh, materials: [textMaterial])
        textEntity.orientation = simd_quatf(angle: -.pi / 2, axis: SIMD3<Float>(1, 0, 0))
        let bounds = textEntity.visualBounds(relativeTo: nil)
        textEntity.position = SIMD3<Float>(-cardWidth * 0.45 - bounds.min.x, cardHeight * 0.34, 0.001)
        root.addChild(textEntity)

        return root
    }

    private func captureCameraFrameOnly(
        onCaptureCompleted: @escaping (ARPlatformPhotoSaveResult) -> Void
    ) {
        guard !isCaptureInProgress else {
            onCaptureCompleted(.failure("正在儲存中，請稍候"))
            return
        }
        guard let arView, let currentFrame = arView.session.currentFrame else {
            onCaptureCompleted(.failure("目前無法取得相機畫面"))
            return
        }

        isCaptureInProgress = true
        // Capture raw camera frame only (no AR overlays / no 3D content / no SwiftUI UI).
        let pixelBuffer = currentFrame.capturedImage
        let interfaceOrientation = currentInterfaceOrientation(for: arView)
        let imageOrientation = imageOrientation(from: interfaceOrientation)

        // 影像轉換與存檔放背景序列佇列，降低主執行緒卡頓。
        photoProcessingQueue.async { [weak self] in
            guard let self else { return }
            guard let image = self.makeUIImage(from: pixelBuffer, orientation: imageOrientation) else {
                self.finishCapture(.failure("擷取影像失敗"), onCaptureCompleted: onCaptureCompleted)
                return
            }
            self.saveImageToPhotoLibrary(image, onCaptureCompleted: onCaptureCompleted)
        }
    }

    private func saveImageToPhotoLibrary(
        _ image: UIImage,
        onCaptureCompleted: @escaping (ARPlatformPhotoSaveResult) -> Void
    ) {
        // Request add-only Photos permission to match "save to album" scope.
        let auth = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch auth {
        case .authorized, .limited:
            persistToPhotoLibrary(image, onCaptureCompleted: onCaptureCompleted)
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
                guard let self else { return }
                if status == .authorized || status == .limited {
                    self.persistToPhotoLibrary(image, onCaptureCompleted: onCaptureCompleted)
                } else {
                    self.finishCapture(
                        .failure("沒有相簿權限，請到設定開啟相簿權限"),
                        onCaptureCompleted: onCaptureCompleted
                    )
                }
            }
        case .denied, .restricted:
            finishCapture(.failure("沒有相簿權限，請到設定開啟相簿權限"), onCaptureCompleted: onCaptureCompleted)
        @unknown default:
            finishCapture(.failure("相簿權限狀態未知，請稍後重試"), onCaptureCompleted: onCaptureCompleted)
        }
    }

    private func persistToPhotoLibrary(
        _ image: UIImage,
        onCaptureCompleted: @escaping (ARPlatformPhotoSaveResult) -> Void
    ) {
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAsset(from: image)
        }) { [weak self] success, _ in
            guard let self else { return }
            if success {
                self.finishCapture(.success, onCaptureCompleted: onCaptureCompleted)
            } else {
                self.finishCapture(.failure("儲存失敗，請稍後重試"), onCaptureCompleted: onCaptureCompleted)
            }
        }
    }

    private func finishCapture(
        _ result: ARPlatformPhotoSaveResult,
        onCaptureCompleted: @escaping (ARPlatformPhotoSaveResult) -> Void
    ) {
        DispatchQueue.main.async {
            // 回到主執行緒統一收尾，確保 SwiftUI 狀態更新時序一致。
            self.isCaptureInProgress = false
            onCaptureCompleted(result)
        }
    }

    private func makeUIImage(from pixelBuffer: CVPixelBuffer, orientation: UIImage.Orientation) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let rect = ciImage.extent
        guard let cgImage = photoCIContext.createCGImage(ciImage, from: rect) else {
            return nil
        }
        return UIImage(cgImage: cgImage, scale: 1.0, orientation: orientation)
    }

    private func imageOrientation(from interfaceOrientation: UIInterfaceOrientation) -> UIImage.Orientation {
        switch interfaceOrientation {
        case .portrait:
            return .right
        case .portraitUpsideDown:
            return .left
        case .landscapeLeft:
            return .up
        case .landscapeRight:
            return .down
        default:
            return .right
        }
    }

    private func currentInterfaceOrientation(for arView: ARView) -> UIInterfaceOrientation {
        guard let windowScene = arView.window?.windowScene else { return .portrait }
        if #available(iOS 26.0, *) {
            return windowScene.effectiveGeometry.interfaceOrientation
        }
        return .portrait
    }
}

extension ARPlatformCameraCoordinator: ARSessionDelegate {
    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        let state = cameraTrackingStateDescription(camera.trackingState)
        guard state != lastPrintedCameraState else { return }
        lastPrintedCameraState = state
        print("Camera tracking state: \(state)")
    }

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        guard let arView else { return }

        for anchor in anchors {
            guard let imageAnchor = anchor as? ARImageAnchor else { continue }
            guard let referenceName = imageAnchor.referenceImage.name else { continue }
            guard referenceName == "platform" else { continue }
            // 同一個 ARImageAnchor 只建立一次對應的 RealityKit Entity。
            guard handledAnchorIDs.insert(imageAnchor.identifier).inserted else { continue }

            let textMesh = MeshResource.generateText(
                "Hello World",
                extrusionDepth: 0.003,
                font: .boldSystemFont(ofSize: 0.06),
                containerFrame: .zero,
                alignment: .center,
                lineBreakMode: .byWordWrapping
            )
            let textMaterial = SimpleMaterial(color: .white, isMetallic: false)
            let textEntity = ModelEntity(mesh: textMesh, materials: [textMaterial])
            textEntity.orientation = simd_quatf(angle: -.pi / 2, axis: SIMD3<Float>(1, 0, 0))

            let bounds = textEntity.visualBounds(relativeTo: nil)
            textEntity.position = SIMD3<Float>(-bounds.center.x, 0.03, -bounds.center.z)

            let anchorEntity = AnchorEntity(anchor: imageAnchor)
            anchorEntity.addChild(textEntity)
            placedAnchorEntities[imageAnchor.identifier] = anchorEntity

            DispatchQueue.main.async {
                arView.scene.addAnchor(anchorEntity)
                self.updateInfoCardEntity(for: imageAnchor.identifier)
            }
        }
    }

    func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        for anchor in anchors {
            guard let imageAnchor = anchor as? ARImageAnchor else { continue }
            guard imageAnchor.referenceImage.name == "platform" else { continue }
            handledAnchorIDs.remove(imageAnchor.identifier)
            placedAnchorEntities[imageAnchor.identifier] = nil
            if let infoCardEntity = infoCardEntities[imageAnchor.identifier] {
                infoCardEntity.removeFromParent()
                infoCardEntities[imageAnchor.identifier] = nil
            }
        }
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard isSessionRunning else { return }
        let now = Date()
        // 節流 + 單工處理，避免每幀都跑模型造成主執行緒與電量壓力。
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
            // 先做 ROI 限制與重疊框合併，再進行輪廓微調，降低雜訊框。
            let inRangeObjects = objects.compactMap(self.clampObjectToROI(_:))
            let mergedObjects = self.mergeOverlappingDetections(inRangeObjects).compactMap(self.clampObjectToROI(_:))
            let refineResult = self.refineDetectionsWithContours(mergedObjects, pixelBuffer: pixelBuffer)
            let clampedRefinedObjects = refineResult.refinedObjects.compactMap(self.clampObjectToROI(_:))
            let inRangeBoxes2D = clampedRefinedObjects.map {
                ARPlatformDetectionBox2D(label: $0.label, confidence: $0.confidence, boundingBox: $0.boundingBox)
            }
            let platformDetected = self.hasTrackedPlatformAnchor(in: frame)

            DispatchQueue.main.async {
                guard self.isSessionRunning else { return }
                self.onDetected(
                    ARPlatformLiveDetectionPayload(
                        objects: objects,
                        inRangeObjects: inRangeObjects,
                        inRangeBoxes2D: inRangeBoxes2D,
                        platformDetected: platformDetected,
                        edgeRefineSuccessCount: refineResult.successCount,
                        edgeRefineFallbackCount: refineResult.fallbackCount
                    )
                )
            }
        }
    }

    private func hasTrackedPlatformAnchor(in frame: ARFrame) -> Bool {
        frame.anchors.contains { anchor in
            guard let imageAnchor = anchor as? ARImageAnchor else { return false }
            return imageAnchor.referenceImage.name == "platform" && imageAnchor.isTracked
        }
    }

    func session(_ session: ARSession, didFailWithError error: any Error) {
        print("AR session failed: \(error.localizedDescription)")
    }

    func sessionWasInterrupted(_ session: ARSession) {
        print("AR session was interrupted")
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        print("AR session interruption ended, restarting")
        guard let arView else { return }
        start(in: arView)
    }

    private func cameraTrackingStateDescription(_ trackingState: ARCamera.TrackingState) -> String {
        switch trackingState {
        case .notAvailable:
            return "notAvailable"
        case .normal:
            return "normal"
        case .limited(let reason):
            switch reason {
            case .initializing:
                return "limited(initializing)"
            case .excessiveMotion:
                return "limited(excessiveMotion)"
            case .insufficientFeatures:
                return "limited(insufficientFeatures)"
            case .relocalizing:
                return "limited(relocalizing)"
            @unknown default:
                return "limited(unknown)"
            }
        }
    }
}

private struct ARPlatformLiveDetectionPayload {
    let objects: [DetectedObject]
    let inRangeObjects: [DetectedObject]
    let inRangeBoxes2D: [ARPlatformDetectionBox2D]
    let platformDetected: Bool
    let edgeRefineSuccessCount: Int
    let edgeRefineFallbackCount: Int

    static let empty = ARPlatformLiveDetectionPayload(
        objects: [],
        inRangeObjects: [],
        inRangeBoxes2D: [],
        platformDetected: false,
        edgeRefineSuccessCount: 0,
        edgeRefineFallbackCount: 0
    )
}

private struct ARPlatformARInfoCardContent: Equatable {
    let category: String
    let material: String
    let handlingSteps: String
    let detailText: String
}

private enum ARPlatformPhotoSaveResult {
    case success
    case failure(String)
}

private struct ARPlatformInlineToast: Identifiable {
    let id = UUID()
    let message: String
    let isSuccess: Bool
}

private struct ARPlatformDetectionBox2D: Identifiable {
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

private struct ARPlatformDetectionCard: Identifiable {
    let id: UUID
    let detection: ARPlatformDetectionBox2D
}

private struct ARPlatformCornerROIOverlay: Shape {
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

private struct ARPlatformROIOutsideMask: Shape {
    let holeRect: CGRect
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addRect(rect)
        p.addRoundedRect(in: holeRect, cornerSize: CGSize(width: cornerRadius, height: cornerRadius))
        return p
    }
}

private struct ARPlatformWasteCardInfo {
    let detectorLabel: String
    let localizedCategoryName: String
    let material: String
    let handlingSteps: String
    let detailText: String

    static func info(for label: String) -> ARPlatformWasteCardInfo {
        let key = label.lowercased()
        let base = mapping[key] ?? fallback
        let localizedCategory = localizedCategoryMapping[key] ?? label
        return ARPlatformWasteCardInfo(
            detectorLabel: label,
            localizedCategoryName: localizedCategory,
            material: base.material,
            handlingSteps: base.handlingSteps,
            detailText: base.detailText
        )
    }

    private static let fallback = ARPlatformWasteCardInfo(
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

    private static let mapping: [String: ARPlatformWasteCardInfo] = [
        "animal waste": ARPlatformWasteCardInfo(
            detectorLabel: "Animal Waste",
            localizedCategoryName: "動物排泄物",
            material: "有機污染物",
            handlingSteps: "使用密封袋分裝，避免與可回收物混放",
            detailText: "動物排泄物通常不屬可回收物，請按一般垃圾或指定有機廢棄渠道處理。"
        ),
        "construction waste": ARPlatformWasteCardInfo(
            detectorLabel: "Construction Waste",
            localizedCategoryName: "建築廢料",
            material: "混合建材",
            handlingSteps: "按材質分堆（木材/金屬/石膏等），交由專門回收或清運",
            detailText: "建築廢料通常不應投入一般回收桶，需使用指定清運或回收渠道。"
        ),
        "garbage bag": ARPlatformWasteCardInfo(
            detectorLabel: "Garbage Bag",
            localizedCategoryName: "垃圾袋",
            material: "混合材質",
            handlingSteps: "先分類袋內物，再處理袋體",
            detailText: "垃圾袋常含污染物，若無法清潔且材質不明，建議按一般垃圾處理。"
        ),
        "glass": ARPlatformWasteCardInfo(
            detectorLabel: "Glass",
            localizedCategoryName: "玻璃",
            material: "玻璃",
            handlingSteps: "清洗、瀝乾、破損時先包裝邊緣",
            detailText: "乾淨玻璃可回收；破碎玻璃請先做好防割包裝再投放。"
        ),
        "metal": ARPlatformWasteCardInfo(
            detectorLabel: "Metal",
            localizedCategoryName: "金屬",
            material: "金屬",
            handlingSteps: "清洗、瀝乾，可行時壓扁",
            detailText: "金屬容器通常可回收，請避免殘留液體或食物污染。"
        ),
        "organic": ARPlatformWasteCardInfo(
            detectorLabel: "Organic",
            localizedCategoryName: "有機物",
            material: "有機物",
            handlingSteps: "瀝乾水分、獨立收集",
            detailText: "有機廢棄物建議走廚餘/堆肥渠道，避免與乾淨可回收物混放。"
        ),
        "plastic": ARPlatformWasteCardInfo(
            detectorLabel: "Plastic",
            localizedCategoryName: "塑膠",
            material: "塑膠",
            handlingSteps: "沖洗乾淨、壓扁、去除內容物",
            detailText: "常見塑膠容器可回收，但受污染或混材包裝可能需一般廢棄。"
        ),
        "paper": ARPlatformWasteCardInfo(
            detectorLabel: "Paper",
            localizedCategoryName: "紙類",
            material: "紙類",
            handlingSteps: "保持乾爽、攤平、移除膠帶",
            detailText: "油污紙與濕紙會降低回收品質，需先清潔再分類。"
        ),
        "waste": ARPlatformWasteCardInfo(
            detectorLabel: "waste",
            localizedCategoryName: "一般垃圾",
            material: "未知/混合",
            handlingSteps: "先嘗試分離可回收部分，其餘密封後棄置",
            detailText: "此類通常代表混合或不明廢棄物，建議先做二次分類再決定去向。"
        )
    ]
}
