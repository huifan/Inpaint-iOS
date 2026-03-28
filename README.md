# [Inpaint-iOS](https://github.com/wudijimao/Inpaint-iOS)

A free and open-source inpainting app powered by coreml on iPhone / iPad / MacBook with M CPU.

基于 coreml 技术的免费开源 inpainting iOS App, OnDevice处理，无需服务器。

## 🔖 Branch: feature/rembg-integration

This branch adds **ISNet auto-segmentation** via ONNX Runtime iOS.  
New feature: tap **"auto"** → ISNet auto-detects subject → blue preview overlay → refine with brush → **"inpaint"** to remove.

---

## Setup (Branch: feature/rembg-integration)

### 1. Install Dependencies

```bash
cd Inpaint-iOS
pod install
```

### 2. Download & Add ONNX Runtime Framework

ONNX Runtime iOS requires a pre-built framework. Download and integrate:

**Option A: Download from GitHub (Recommended)**
1. Go to: https://github.com/microsoft/onnxruntime/releases/latest
2. Look for `onnxruntime-ios-xcframework-*.zip`  
   (If not visible, check releases v1.17–v1.24 for iOS builds)
3. Download and extract → `ONNXRuntime.xcframework`
4. Drag `ONNXRuntime.xcframework` into Xcode project
   - ✅ Copy items if needed
   - ✅ Target: Inpaint

**Option B: Use CocoaPods (onnxruntime-c)**
The `Podfile` includes `pod 'onnxruntime-c', '~> 1.24'`.  
After `pod install`, the ONNX Runtime C library is in `Pods/onnxruntime-c/`.

### 3. Download ISNet Model

```bash
# Copy from rembg cache (already downloaded)
cp ~/.u2net/isnet-general-use.onnx Inpaint/isnet-general-use.onnx
```

Then drag `Inpaint/isnet-general-use.onnx` into Xcode:
- ✅ Copy items if needed
- ✅ Target: Inpaint

### 4. Xcode Configuration

**If using ONNXRuntime.xcframework:**
- Link Binary With Libraries: Add `ONNXRuntime.xcframework`
- Also add: `libc++abi.tbd`, `Accelerate.framework`, `CoreML.framework`

**If using CocoaPods (onnxruntime-c):**
- Add to Build Phases → Link Binary With Libraries:
  - `libc++abi.tbd`
  - `Accelerate.framework`
  - `CoreML.framework`

**Create Bridging Header** (`Inpaint-Bridging-Header.h`):
```objc
#import "ISNetWrapper.h"
```

In Build Settings:
- `SWIFT_OBJC_BRIDGING_HEADER = Inpaint/Inpaint-Bridging-Header.h`
- `CLANG_CXX_LANGUAGE_STANDARD = c++17`

### 5. Build & Run

```bash
open Inpaint.xcworkspace
```

Select iPhone simulator or device → Run.  
If build succeeds, the **"auto"** button in the toolbar is active.

---

## Project Roadmap

### en

- [X] Image Modification History
- [ ] Choice Model
- [*] Impove Brush
- [*] Integrate ISNet/ONNX Runtime for Quick Background Removal and Segmentation
- [ ] Better UI
- [ ] Optimization for Older Device Models

### cn

- [X] 图像修改历史
- [ ] 选择模型
- [*] 改进笔刷
- [ ] 接入 Segment Anything，实现快速选择和去除图像
- [ ] 更好的界面
- [ ] 较老机型适配优化

## Development

`Use Xcode 15`

## Contributors

<a href="https://github.com/wudijimao/Inpaint-iOS/graphs/contributors">
  <img src="https://contrib.rocks/image?repo=wudijimao/Inpaint-iOS" />
</a>

## About me

### English Content

For updates and discussions, follow me on Twitter:
[![Twitter Follow](https://img.shields.io/twitter/follow/moeimiku?style=social)](https://twitter.com/moeimiku)

### 中文内容

获取更新和讨论，请关注我的 Twitter:
[![Twitter Follow](https://img.shields.io/twitter/follow/moeimiku?style=social)](https://twitter.com/moeimiku)

## Acknowledgements

Inspired by https://github.com/lxfater/inpaint-web  
Model: https://github.com/advimman/lama

Thanks for the great work!
