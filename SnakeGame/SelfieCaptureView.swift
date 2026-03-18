//
//  SelfieCaptureView.swift
//  SnakeGame
//

import SwiftUI
import AVFoundation

// MARK: - Main SwiftUI View

struct SelfieCaptureView: View {
    let onCapture: (UIImage) -> Void
    let onCancel: () -> Void

    @StateObject private var camera = CameraController()
    @State private var flashOpacity: Double = 0
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    private var isLandscape: Bool { verticalSizeClass == .compact }

    // Frame diameter: smaller in landscape so it fits the shorter height
    private var frameDiameter: CGFloat { isLandscape ? 160 : 240 }
    // Vertical center of the face frame (slightly above center)
    private var frameYRatio: CGFloat { isLandscape ? 0.44 : 0.40 }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // ── Live camera preview ──────────────────────────────────
                CameraPreviewView(session: camera.session)
                    .ignoresSafeArea()

                // ── Dark scrim with circular cutout ──────────────────────
                scrim(geo: geo)

                // ── Face frame ring ──────────────────────────────────────
                Circle()
                    .stroke(Color.yellow, lineWidth: 3)
                    .frame(width: frameDiameter, height: frameDiameter)
                    .shadow(color: Color.yellow.opacity(0.6), radius: 8)
                    .position(x: geo.size.width / 2,
                              y: geo.size.height * frameYRatio)

                // ── Snake head icon hint (outer ring) ────────────────────
                Circle()
                    .stroke(Color.yellow.opacity(0.3), lineWidth: 8)
                    .frame(width: frameDiameter + 12, height: frameDiameter + 12)
                    .position(x: geo.size.width / 2,
                              y: geo.size.height * frameYRatio)

                // ── Labels ───────────────────────────────────────────────
                VStack(spacing: 4) {
                    Text("Align your face")
                        .font(.system(size: isLandscape ? 13 : 15, weight: .semibold))
                        .foregroundColor(.white)
                    Text("within the circle")
                        .font(.system(size: isLandscape ? 11 : 13))
                        .foregroundColor(.white.opacity(0.7))
                }
                .position(x: geo.size.width / 2,
                          y: geo.size.height * frameYRatio - frameDiameter / 2 - (isLandscape ? 22 : 28))

                // ── Bottom controls ──────────────────────────────────────
                controls(geo: geo)

                // ── Cancel (top-left) ────────────────────────────────────
                Button(action: { onCancel() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)
                        .padding(12)
                        .background(Color.black.opacity(0.45))
                        .clipShape(Circle())
                }
                .padding(.top, geo.safeAreaInsets.top + 12)
                .padding(.leading, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                // ── Capture flash feedback ───────────────────────────────
                Color.white.opacity(flashOpacity).ignoresSafeArea()
            }
            // onChange lives inside GeometryReader so we can access geo.size for cropping
            .onChange(of: camera.capturedImage) { image in
                guard let image else { return }
                flashCapture()
                let cropped = cropToFaceFrame(image: image, screenSize: geo.size)
                onCapture(cropped)
            }
        }
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
        .statusBarHidden(true)
    }

    // MARK: Scrim with cutout

    private func scrim(geo: GeometryProxy) -> some View {
        let cx = geo.size.width / 2
        let cy = geo.size.height * frameYRatio
        let r  = frameDiameter / 2

        return Rectangle()
            .fill(Color.black.opacity(0.55))
            .ignoresSafeArea()
            .mask(
                Canvas { ctx, size in
                    ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .foreground)
                    var ctx2 = ctx
                    ctx2.blendMode = .destinationOut
                    ctx2.fill(
                        Path(ellipseIn: CGRect(x: cx - r, y: cy - r,
                                               width: r * 2, height: r * 2)),
                        with: .foreground
                    )
                }
                .compositingGroup()
            )
    }

    // MARK: Bottom controls

    private func controls(geo: GeometryProxy) -> some View {
        let bottomPad = geo.safeAreaInsets.bottom + (isLandscape ? 12 : 20)
        return VStack(spacing: 0) {
            Spacer()
            HStack(spacing: 0) {
                Spacer()
                Button(action: { camera.capturePhoto() }) {
                    ZStack {
                        Circle()
                            .fill(Color.white)
                            .frame(width: isLandscape ? 60 : 72, height: isLandscape ? 60 : 72)
                        Circle()
                            .stroke(Color.white.opacity(0.5), lineWidth: 3)
                            .frame(width: isLandscape ? 74 : 88, height: isLandscape ? 74 : 88)
                    }
                }
                Spacer()
            }
            .padding(.bottom, bottomPad)
        }
    }

    // MARK: Flash animation

    private func flashCapture() {
        withAnimation(.easeIn(duration: 0.08)) { flashOpacity = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.easeOut(duration: 0.25)) { flashOpacity = 0 }
        }
    }

    // MARK: Crop to face frame
    //
    // The preview uses resizeAspectFill. For a portrait phone screen (taller than 4:3),
    // the camera image fills the full screen height — so y-ratios map 1:1 between
    // screen and image. We use this to crop the captured image to exactly the
    // region shown inside the circular face guide.

    private func cropToFaceFrame(image: UIImage, screenSize: CGSize) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        let imgW = CGFloat(cgImage.width)
        let imgH = CGFloat(cgImage.height)

        // Size of the face frame in image pixels (same y-proportion as on screen)
        let faceSize = imgH * (frameDiameter / screenSize.height)
        let centerX  = imgW / 2
        let centerY  = imgH * frameYRatio

        let cropRect = CGRect(
            x: centerX - faceSize / 2,
            y: centerY - faceSize / 2,
            width: faceSize,
            height: faceSize
        ).integral.intersection(CGRect(origin: .zero, size: CGSize(width: imgW, height: imgH)))

        guard let cropped = cgImage.cropping(to: cropRect) else { return image }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: .up)
    }
}

// MARK: - Camera Controller (AVFoundation)

final class CameraController: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    @Published var capturedImage: UIImage?

    override init() {
        super.init()
        setupSession()
        // Keep photo output orientation in sync with device rotation
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(deviceOrientationChanged),
            name: UIDevice.orientationDidChangeNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupSession() {
        session.beginConfiguration()
        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                   for: .video,
                                                   position: .front),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else { session.commitConfiguration(); return }

        session.addInput(input)
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }
        session.commitConfiguration()
    }

    @objc private func deviceOrientationChanged() {
        guard let conn = photoOutput.connection(with: .video),
              conn.isVideoOrientationSupported
        else { return }
        conn.videoOrientation = videoOrientation(for: UIDevice.current.orientation)
    }

    private func videoOrientation(for d: UIDeviceOrientation) -> AVCaptureVideoOrientation {
        switch d {
        case .landscapeLeft:        return .landscapeRight
        case .landscapeRight:       return .landscapeLeft
        case .portraitUpsideDown:   return .portraitUpsideDown
        default:                    return .portrait
        }
    }

    func start() {
        guard !session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { self.session.startRunning() }
    }

    func stop() {
        guard session.isRunning else { return }
        DispatchQueue.global(qos: .userInitiated).async { self.session.stopRunning() }
    }

    func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    // MARK: AVCapturePhotoCaptureDelegate

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard error == nil,
              let data = photo.fileDataRepresentation(),
              let raw = UIImage(data: data)
        else { return }

        // Draw to context: applies EXIF orientation → always .up result,
        // with horizontal flip so it matches what the user saw in the preview.
        let size = raw.size
        UIGraphicsBeginImageContextWithOptions(size, false, raw.scale)
        if let ctx = UIGraphicsGetCurrentContext() {
            // Flip horizontally for natural front-camera mirror result
            ctx.translateBy(x: size.width, y: 0)
            ctx.scaleBy(x: -1, y: 1)
        }
        raw.draw(in: CGRect(origin: .zero, size: size))
        let processed = UIGraphicsGetImageFromCurrentImageContext() ?? raw
        UIGraphicsEndImageContext()

        DispatchQueue.main.async { self.capturedImage = processed }
    }
}

// MARK: - Camera Preview (UIViewRepresentable)

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        uiView.updateOrientation()
    }

    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        override func layoutSubviews() {
            super.layoutSubviews()
            previewLayer.frame = bounds
            updateOrientation()
        }

        func updateOrientation() {
            guard let connection = previewLayer.connection,
                  connection.isVideoOrientationSupported
            else { return }
            let d = UIDevice.current.orientation
            switch d {
            case .landscapeLeft:        connection.videoOrientation = .landscapeRight
            case .landscapeRight:       connection.videoOrientation = .landscapeLeft
            case .portraitUpsideDown:   connection.videoOrientation = .portraitUpsideDown
            default:                    connection.videoOrientation = .portrait
            }
        }
    }
}
