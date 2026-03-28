//
//  ISNetWrapper.mm
//  Inpaint
//
//  ISNet inference using ONNX Runtime C API on iOS.
//  Supports both ONNXRuntime.xcframework and onnxruntime-c CocoaPod.
//
//  Framework setup:
//    Option A (xcframework): #include <onnxruntime_c_api.h>
//    Option B (CocoaPods):  #include <onnxruntime_c_api.h>
//      (Headers at: Pods/onnxruntime-c/include/onnxruntime_c_api.h)
//      Link with: Pods/onnxruntime-c/libonnxruntime.a
//

#import "ISNetWrapper.h"
#import <onnxruntime_c_api.h>
#import <CoreML/CoreML.h>
#import <Accelerate/Accelerate.h>

@implementation ISNetResult
@end

@interface ISNetWrapper ()
@property (nonatomic, assign) OrtEnv *env;
@property (nonatomic, assign) OrtSession *session;
@property (nonatomic, assign) OrtSessionOptions *sessionOptions;
@property (nonatomic, strong) NSString *inputName;
@property (nonatomic, strong) NSString *outputName;
@property (nonatomic, strong) dispatch_queue_t workQueue;
@property (nonatomic, assign) NSInteger inputSize;
@end

@implementation ISNetWrapper

+ (instancetype)shared {
    static ISNetWrapper *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [[ISNetWrapper alloc] init]; });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _inputSize = 1024; // ISNet input: 1024x1024
        _workQueue = dispatch_queue_create("com.inpaint.isnet", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (BOOL)loadModel:(NSString *)modelName error:(NSError **)error {
    // Find model file in bundle
    NSString *modelPath = [[NSBundle mainBundle] pathForResource:modelName ofType:@"onnx"];
    if (!modelPath) {
        if (error) {
            *error = [NSError errorWithDomain:@"ISNetWrapper"
                                         code:101
                                     userInfo:@{NSLocalizedDescriptionKey:
                                         [NSString stringWithFormat:@"Model '%@.onnx' not found in bundle. Did you forget to add the file to the Xcode project?", modelName]}];
        }
        return NO;
    }

    // Create ONNX Runtime environment
    OrtStatus *status = OrtCreateEnv(ORT_LOGGING_LEVEL_WARNING, "ISNet", &(_env));
    if (status != NULL) {
        if (error) *error = [self errorFromStatus:status code:102 msg:@"Failed to create ONNX Runtime environment"];
        return NO;
    }

    // Create session options
    status = OrtCreateSessionOptions(&(_sessionOptions));
    if (status != NULL) {
        if (error) *error = [self errorFromStatus:status code:103 msg:@"Failed to create session options"];
        return NO;
    }

    // Enable CoreML execution provider (uses Apple Neural Engine on iOS)
    // Falls back to CPU if CoreML unavailable
    status = OrtSessionOptionsAppendExecutionProvider(_sessionOptions, "CoreML");
    if (status != NULL) {
        NSLog(@"[ISNet] Warning: CoreML EP registration returned non-null status, continuing anyway");
    }

    // Create inference session
    status = OrtCreateSession(_env, [modelPath UTF8String], _sessionOptions, &(_session));
    if (status != NULL) {
        if (error) *error = [self errorFromStatus:status code:104 msg:@"Failed to create inference session"];
        return NO;
    }

    // Get input/output tensor names
    OrtAllocator *allocator = NULL;
    OrtGetAllocator(&allocator);
    
    char *inputNameCStr = NULL;
    OrtStatus *s = OrtGetInputName(_session, 0, allocator, &inputNameCStr);
    if (s == NULL && inputNameCStr != NULL) {
        self.inputName = [NSString stringWithUTF8String:inputNameCStr];
    } else {
        self.inputName = @"input_image"; // fallback default
    }
    allocator->Free(allocator, inputNameCStr);
    
    char *outputNameCStr = NULL;
    s = OrtGetOutputName(_session, 0, allocator, &outputNameCStr);
    if (s == NULL && outputNameCStr != NULL) {
        self.outputName = [NSString stringWithUTF8String:outputNameCStr];
    } else {
        self.outputName = @"output_image"; // fallback default
    }
    allocator->Free(allocator, outputNameCStr);

    NSLog(@"[ISNet] Model loaded. Input: %@, Output: %@", self.inputName, self.outputName);
    return YES;
}

- (nullable UIImage *)predict:(UIImage *)image error:(NSError **)error {
    if (!_session) {
        if (error) {
            *error = [NSError errorWithDomain:@"ISNetWrapper"
                                         code:103
                                     userInfo:@{NSLocalizedDescriptionKey: @"Model not loaded. Call loadModel:error: first."}];
        }
        return nil;
    }

    NSInteger size = self.inputSize; // 1024

    // Step 1: Resize input image to model size
    CGSize targetSize = CGSizeMake(size, size);
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:targetSize];
    UIImage *resized = [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull context) {
        [image drawInRect:CGRectMake(0, 0, size, size)];
    }];

    // Step 2: Extract RGB pixel bytes from UIImage
    CGImageRef cg = resized.CGImage;
    size_t width = (size_t)size, height = (size_t)size;
    size_t bytesPerRow = width * 4;
    uint8_t *rawPixels = (uint8_t *)malloc(bytesPerRow * height);
    
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(rawPixels, width, height, 8, bytesPerRow,
                                              colorSpace,
                                              kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGContextDrawImage(ctx, CGRectMake(0, 0, width, height), cg);
    CGContextRelease(ctx);
    CGColorSpaceRelease(colorSpace);

    // Step 3: Convert to CHW Float32 tensor [0,1]
    // ISNet expects (1, 3, 1024, 1024) in CHW format
    size_t floatCount = 3 * size * size;
    float *inputTensor = (float *)malloc(floatCount * sizeof(float));
    
    for (NSInteger y = 0; y < size; y++) {
        for (NSInteger x = 0; x < size; x++) {
            size_t pixelIdx = (y * size + x) * 4;
            float r = rawPixels[pixelIdx] / 255.0f;
            float g = rawPixels[pixelIdx + 1] / 255.0f;
            float b = rawPixels[pixelIdx + 2] / 255.0f;
            
            // CHW layout: all R values first, then G, then B
            size_t rIdx = y * size + x;
            size_t gIdx = size * size + y * size + x;
            size_t bIdx = 2 * size * size + y * size + x;
            inputTensor[rIdx] = r;
            inputTensor[gIdx] = g;
            inputTensor[bIdx] = b;
        }
    }
    free(rawPixels);

    // Step 4: Create ONNX Runtime tensor
    OrtMemoryInfo *memInfo = NULL;
    OrtCreateMemoryInfo("Cpu", OrtArenaAllocator, 0, OrtMemTypeDefault, &memInfo);
    
    int64_t inputShape[] = {1, 3, size, size};
    OrtValue *inputValue = NULL;
    OrtCreateTensorWithData(memInfo, inputTensor, floatCount * sizeof(float),
                            inputShape, 4, ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, &inputValue);
    OrtReleaseMemoryInfo(memInfo);
    free(inputTensor);

    // Step 5: Run inference
    const char *inputNames[] = {[self.inputName UTF8String]};
    const char *outputNames[] = {[self.outputName UTF8String]};
    
    OrtValue *outputValue = NULL;
    OrtStatus *runStatus = OrtRun(_session, NULL,
                                  inputNames, (const OrtValue**)&inputValue, 1,
                                  outputNames, 1, &outputValue);
    OrtReleaseValue(inputValue);

    if (runStatus != NULL || !outputValue) {
        if (error) *error = [self errorFromStatus:runStatus code:104 msg:@"ONNX Runtime inference failed"];
        return nil;
    }

    // Step 6: Get output tensor dimensions
    int64_t outShape[4];
    size_t numDims = 4;
    OrtGetDimensions(outputValue, outShape, numDims);
    int64_t outH = outShape[2];
    int64_t outW = outShape[3];

    // Step 7: Read output tensor data (Float32, range [0, 1])
    float *outputData = (float *)OrtGetTensorData(outputValue);

    // Step 8: Convert to grayscale UIImage
    size_t maskByteCount = outH * outW;
    uint8_t *maskBytes = (uint8_t *)malloc(maskByteCount);
    
    for (NSInteger i = 0; i < maskByteCount; i++) {
        float v = outputData[i];
        v = fminf(1.0f, fmaxf(0.0f, v)); // clamp
        maskBytes[i] = (uint8_t)(v * 255.0f);
    }

    CGColorSpaceRef graySpace = CGColorSpaceCreateDeviceGray();
    CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, maskBytes, maskByteCount, NULL);
    CGImageRef maskCG = CGImageCreate(outW, outH, 8, 8, (size_t)outW,
                                       graySpace, kCGImageAlphaNone,
                                       provider, NULL, false, kCGRenderingIntentDefault);
    CGDataProviderRelease(provider);
    CGColorSpaceRelease(graySpace);
    free(maskBytes);
    OrtReleaseValue(outputValue);

    UIImage *maskImage = [UIImage imageWithCGImage:maskCG];
    CGImageRelease(maskCG);
    
    return maskImage;
}

- (void)predictAsync:(UIImage *)image completion:(void (^)(ISNetResult *))completion {
    dispatch_async(self.workQueue, ^{
        NSError *error = nil;
        UIImage *mask = [self predict:image error:&error];
        
        ISNetResult *result = [[ISNetResult alloc] init];
        result.maskImage = mask;
        result.success = (mask != nil);
        result.error = error;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(result);
        });
    });
}

- (NSError *)errorFromStatus:(OrtStatus *)status code:(NSInteger)code msg:(NSString *)msg {
    if (status == NULL) return nil;
    const char *statusMsg = OrtGetErrorMessage(status);
    NSString *msgStr = [NSString stringWithFormat:@"%@: %s", msg, statusMsg ? statusMsg : "unknown"];
    return [NSError errorWithDomain:@"ISNetWrapper" code:code userInfo:@{NSLocalizedDescriptionKey: msgStr}];
}

- (void)dealloc {
    if (_session) OrtReleaseSession(_session);
    if (_sessionOptions) OrtReleaseSessionOptions(_sessionOptions);
    if (_env) OrtReleaseEnv(_env);
}

@end
