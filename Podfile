# Uncomment the next line to define a global platform for your project
platform :ios, '15.0'

target 'Inpaint' do
  # Comment the next line if you don't want to use dynamic frameworks
  use_frameworks! :linkage => :static

  pod 'SnapKit'
  pod 'Toast-Swift'
  # Note: ONNX Runtime iOS uses pre-built framework from GitHub releases.
  # Download from: https://github.com/microsoft/onnxruntime/releases
  # Recommended: onnxruntime-ios-1.17.0.zip (static framework with CoreML EP)

  # Pods for Inpaint

  target 'InpaintTests' do
    inherit! :search_paths
    # Pods for testing
  end

  target 'InpaintUITests' do
    # Pods for testing
  end

end
