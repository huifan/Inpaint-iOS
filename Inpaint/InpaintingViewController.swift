//
//  InpaintingViewController.swift
//  Inpaint
//
//  Created by wudijimao on 2023/12/13.
//

import UIKit
import SnapKit
import Toast_Swift

class InpaintingViewController: UIViewController {
    
    var inpenting = LaMaImageInpenting.init()
    var loadngView = UIActivityIndicatorView(style: .large)

    lazy var scrollView: UIScrollView = {
        let scrollView = UIScrollView(frame: .zero)
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 6.0
        view.addSubview(scrollView)
        return scrollView
    }()
    var imageView = UIImageView()
    
    lazy var drawView: SmudgeDrawingView = {
        let view = SmudgeDrawingView.init()
        return view
    }()
    
    public init(image: UIImage) {
        super.init(nibName: nil, bundle: nil)
        imageView.image = image
        imageView.backgroundColor = .red
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    lazy var unDoButton = UIBarButtonItem(title: *"undo", style: .plain, target: self, action: #selector(onUndo))
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .systemBackground
        
        view.addSubview(scrollView)
        scrollView.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.top.equalTo(self.view.safeAreaLayoutGuide.snp.top)
            make.bottom.equalTo(self.view.safeAreaLayoutGuide.snp.bottom)
        }
        scrollView.addSubview(imageView)
        imageView.backgroundColor = .systemBackground
        imageView.contentMode = .scaleAspectFit
        imageView.snp.makeConstraints { make in
            make.width.equalToSuperview()
            make.height.equalToSuperview()
        }
        
        imageView.addSubview(drawView)
        imageView.isUserInteractionEnabled = true
        drawView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        unDoButton.isEnabled = false
        
        // Navigation bar: [Save] [Inpaint] [Auto(ISNet)] [Undo]
        let clearButton = UIBarButtonItem(title: *"inpaint", style: .plain, target: self, action: #selector(onInpaint))
        let saveButton = UIBarButtonItem(title: *"save_to_photo_lib", style: .plain, target: self, action: #selector(onSave))
        let autoButton = UIBarButtonItem(title: "auto", style: .plain, target: self, action: #selector(onAutoRemove))
        
        navigationItem.rightBarButtonItems = [saveButton, clearButton, autoButton, unDoButton]
        
        loadngView.hidesWhenStopped = true
        view.addSubview(loadngView)
        loadngView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        // Brush size slider
        let slider = UISlider()
        slider.minimumValue = 10
        slider.maximumValue = 50
        let lastSliderValue = UserDefaults.standard.object(forKey: "lastSliderValue") as? Float ?? 30
        slider.value = lastSliderValue
        slider.addTarget(self, action: #selector(sliderValueChanged(_:)), for: .valueChanged)
        drawView.brushSize = CGFloat(lastSliderValue)
        
        let sliderBarItem = UIBarButtonItem(customView: slider)
        self.navigationItem.titleView = sliderBarItem.customView
        slider.widthAnchor.constraint(equalToConstant: self.view.frame.width - 320).isActive = true
        
        // Preload ISNet model
        ISNetService.shared.preload()
    }
    
    @objc func sliderValueChanged(_ sender: UISlider) {
        let roundedValue = round(sender.value)
        UserDefaults.standard.set(roundedValue, forKey: "lastSliderValue")
        drawView.brushSize = CGFloat(roundedValue)
    }
    
    var undoList = [UIImage]() {
        didSet {
            unDoButton.isEnabled = undoList.count > 0
        }
    }
    
    @objc func onUndo() {
        guard undoList.count > 0 else { return }
        let img = undoList.removeLast()
        self.imageView.image = img
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        if undoList.count > 3 {
            let lastTwo = undoList.suffix(2)
            undoList = [undoList[0]] + lastTwo
        }
    }
    
    var hasWarned = false

    @objc func onInpaint() {
        guard let inputImage = imageView.image else { return }
        guard let maskImage = drawView.exportAsGrayscaleImage() else { return }
        loadngView.startAnimating()
        let bounds = drawView.drawBounds
        if !hasWarned, let rect = bounds.first, (rect.size.width > 512 || rect.size.height > 512) {
            hasWarned = true
            self.view.makeToast(*"toast_inpaint_warning", duration: 4.0, position: .bottom)
        }
        inpenting.inpent(image: inputImage, mask: maskImage, inpaintingRects: bounds) { [weak self] outImage, err in
            guard let self = self else { return }
            self.imageView.image = outImage
            self.imageView.contentMode = .scaleAspectFit
            self.undoList.append(inputImage)
            self.drawView.clean()
            self.loadngView.stopAnimating()
        }
    }
    
    // MARK: - ISNet Auto Segmentation
    
    /// "Auto" button: run ISNet on full image → show mask as blue overlay preview.
    /// User can refine with brush, then tap "inpaint".
    @objc func onAutoRemove() {
        guard let inputImage = imageView.image else {
            self.view.makeToast("No image loaded", duration: 2.0, position: .bottom)
            return
        }
        
        loadngView.startAnimating()
        self.view.makeToast("Running auto-segmentation...", duration: 1.0, position: .center)
        
        ISNetService.shared.predictAsync(inputImage: inputImage) { [weak self] result in
            guard let self = self else { return }
            self.loadngView.stopAnimating()
            
            guard result.success, let maskImage = result.maskImage else {
                let msg = result.error?.localizedDescription ?? "ISNet failed"
                self.view.makeToast(msg, duration: 3.0, position: .bottom)
                return
            }
            
            // Transform mask to match display coordinates:
            // ISNet mask is 1024x1024, but image was letterboxed to fit.
            // Return inverted mask so draw() and export() can both use it directly.
            let displayMask = self.resizeAndInvertMaskForDisplay(
                maskImage,
                displaySize: self.imageView.bounds.size,
                originalImageSize: inputImage.size
            )
            
            self.drawView.isnetMaskOverlay = displayMask
            self.view.makeToast(
                "Auto-detection done! Blue = detected subject. Refine with brush, then tap Inpaint.",
                duration: 3.5,
                position: .bottom
            )
        }
    }
    
    /// Resize and invert ISNet mask to match display coordinates.
    /// ISNet output: white=subject(keep), black=background(remove).
    /// After inversion here: white=background(remove, blue in preview), black=subject(keep).
    /// This mask can be used directly for both:
    ///   - draw(): clip with white=blue, black=transparent
    ///   - exportAsGrayscaleImage(): white=inpaint, black=preserve
    private func resizeAndInvertMaskForDisplay(_ mask: UIImage, displaySize: CGSize, originalImageSize: CGSize) -> UIImage {
        // Compute aspect-fit scaling of original within displaySize
        let scale = min(displaySize.width / originalImageSize.width,
                       displaySize.height / originalImageSize.height)
        let scaledImageSize = CGSize(
            width: originalImageSize.width * scale,
            height: originalImageSize.height * scale
        )
        let offsetX = (displaySize.width - scaledImageSize.width) / 2.0
        let offsetY = (displaySize.height - scaledImageSize.height) / 2.0
        
        // Scale mask from 1024x1024 to scaled image size
        let scaledMask: UIImage = UIGraphicsImageRenderer(size: scaledImageSize).image { ctx in
            mask.draw(in: CGRect(origin: .zero, size: scaledImageSize))
        }
        
        // Paste scaled mask onto displaySize canvas at offset
        UIGraphicsBeginImageContextWithOptions(displaySize, false, 1.0)
        if let ctx = UIGraphicsGetCurrentContext() {
            ctx.clear(CGRect(origin: .zero, size: displaySize))
            if let sm = scaledMask.cgImage {
                let maskRect = CGRect(origin: CGPoint(x: offsetX, y: offsetY), size: scaledImageSize)
                ctx.draw(sm, in: maskRect)
            }
        }
        let preInvert = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        guard let preInvertImg = preInvert else { return mask }
        
        // Invert the mask: white↔black
        guard let inverted = preInvertImg.invertedGrayscale() else { return preInvertImg }
        return inverted
    }
    
    @objc func onSave() {
        guard let imageToSave = imageView.image else {
            print("No image to save")
            return
        }
        UIImageWriteToSavedPhotosAlbum(imageToSave, self, #selector(image(_:didFinishSavingWithError:contextInfo:)), nil)
    }
    
    @objc func image(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        if let error = error {
            self.view.makeToast("Save failed: \(error.localizedDescription)", duration: 3.0, position: .bottom)
        } else {
            self.view.makeToast("Saved!", duration: 3.0, position: .bottom)
        }
    }
}

extension InpaintingViewController: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return imageView
    }
    
    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        // TODO: handle brush size after zoom
    }
}
