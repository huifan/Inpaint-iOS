//
//  ISNetWrapper.h
//  Inpaint
//
//  Objective-C wrapper for ONNX Runtime C API on iOS.
//  Provides ISNet model inference for auto-segmentation.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Result of ISNet prediction.
@interface ISNetResult : NSObject
@property (nonatomic, strong, nullable) UIImage *maskImage;
@property (nonatomic, assign) BOOL success;
@property (nonatomic, strong, nullable) NSError *error;
@end

/// ISNet inference service using ONNX Runtime C API.
/// Thread-safe, supports async prediction.
@interface ISNetWrapper : NSObject

+ (instancetype)shared;

/// Load model from bundle. Call once at startup.
/// @param modelName Filename without extension (e.g. @"isnet-general-use")
/// @param error On failure, populated with error info.
/// @return YES on success.
- (BOOL)loadModel:(NSString *)modelName error:(NSError **)error;

/// Synchronous prediction. Call from background thread.
/// @param image Input UIImage (any size, will be resized to model input)
/// @param error On failure, populated with error info.
/// @return Grayscale mask UIImage (white=subject, black=background). Nil on error.
- (nullable UIImage *)predict:(UIImage *)image error:(NSError **)error;

/// Async prediction. Completes on background thread, result delivered to main queue.
/// @param image Input UIImage
/// @param completion Called on main queue with result.
- (void)predictAsync:(UIImage *)image
          completion:(void (^)(ISNetResult *result))completion;

/// Model input dimensions (ISNet: 1024x1024)
@property (nonatomic, readonly) NSInteger inputSize;

@end

NS_ASSUME_NONNULL_END
