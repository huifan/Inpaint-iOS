//
//  ISNetWrapper.mm
//  Inpaint
//
//  ISNet inference using ONNX Runtime C API on iOS.
//  Uses CocoaPods onnxruntime-c (1.24.3).
//

#import "ISNetWrapper.h"
#import <onnxruntime_c_api.h>
#import <coreml_provider_factory.h>
#import <Accelerate/Accelerate.h>

@implementation ISNetResult
@end

@interface ISNetWrapper ()
@property (nonatomic, assign) const OrtApi *ort;
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
        _inputSize = 1024;
        _workQueue = dispatch_queue_create("com.inpaint.isnet", DISPATCH_QUEUE_SERIAL);
        const OrtApiBase *ortBase = OrtGetApiBase();
        _ort = ortBase->GetApi(ORT_API_VERSION);
    }
    return self;
}

- (BOOL)loadModel:(NSString *)modelName error:(NSError **)error {
    NSString *modelPath = [[NSBundle mainBundle] pathForResource:modelName ofType:@"onnx"];
    if (!modelPath) {
        if (error) {
            *error = [NSError errorWithDomain:@"ISNetWrapper"
                                         code:101
                                     userInfo:@{NSLocalizedDescriptionKey:
                                         [NSString stringWithFormat:@"Model '%@.onnx' not found in bundle.", modelName]}];
        }
        return NO;
    }

    // Create environment
    OrtEnv *env = NULL;
    OrtStatus *status = _ort->CreateEnv(ORT_LOGGING_LEVEL_WARNING, "ISNet", &env);
    if (status != NULL) {
        if (error) *error = [self errorFromStatus:status code:102 msg:@"Failed to create environment"];
        return NO;
    }
    _env = env;

    // Create session options
    OrtSessionOptions *opts = NULL;
    status = _ort->CreateSessionOptions(&opts);
    if (status != NULL) {
        if (error) *error = [self errorFromStatus:status code:103 msg:@"Failed to create session options"];
        return NO;
    }
    _sessionOptions = opts;

    // Enable CoreML EP (Apple Neural Engine on iOS)
    OrtSessionOptionsAppendExecutionProvider_CoreML(_sessionOptions, 0);

    // Create session
    OrtSession *sess = NULL;
    status = _ort->CreateSession(_env, [modelPath UTF8String], _sessionOptions, &sess);
    if (status != NULL) {
        if (error) *error = [self errorFromStatus:status code:104 msg:@"Failed to create session"];
        return NO;
    }
    _session = sess;

    // Get input/output names
    OrtAllocator *allocator = NULL;
    _ort->GetAllocatorWithDefaultOptions(&allocator);

    char *inputNameCStr = NULL;
    OrtStatus *s = _ort->SessionGetInputName(_session, 0, allocator, &inputNameCStr);
    if (s == NULL && inputNameCStr != NULL) {
        self.inputName = [NSString stringWithUTF8String:inputNameCStr];
    } else {
        self.inputName = @"input_image";
    }
    if (inputNameCStr) allocator->Free(allocator, inputNameCStr);

    char *outputNameCStr = NULL;
    s = _ort->SessionGetOutputName(_session, 0, allocator, &outputNameCStr);
    if (s == NULL && outputNameCStr != NULL) {
        self.outputName = [NSString stringWithUTF8String:outputNameCStr];
    } else {
        self.outputName = @"output_image";
    }
    if (outputNameCStr) allocator->Free(allocator, outputNameCStr);

    NSLog(@"[ISNet] Loaded! Input: %@, Output: %@", self.inputName, self.outputName);
    return YES;
}

- (nullable UIImage *)predict:(UIImage *)image error:(NSError **)error {
    if (!_session || !_ort) {
        if (error) {
            *error = [NSError errorWithDomain:@"ISNetWrapper"
                                         code:103
                                     userInfo:@{NSLocalizedDescriptionKey: @"Model not loaded."}];
        }
        return nil;
    }

    NSInteger size = self.inputSize; // 1024

    // Step 1: Resize to 1024x1024
    CGSize targetSize = CGSizeMake(size, size);
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:targetSize];
    UIImage *resized = [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull context) {
        [image drawInRect:CGRectMake(0, 0, size, size)];
    }];

    // Step 2: Get RGB pixel bytes from UIImage
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

    // Step 3: Convert to CHW Float32 [0,1] tensor: (1, 3, 1024, 1024)
    size_t floatCount = 3 * size * size;
    float *inputTensor = (float *)malloc(floatCount * sizeof(float));

    for (NSInteger y = 0; y < size; y++) {
        for (NSInteger x = 0; x < size; x++) {
            size_t pixelIdx = (y * size + x) * 4;
            float r = rawPixels[pixelIdx] / 255.0f;
            float g = rawPixels[pixelIdx + 1] / 255.0f;
            float b = rawPixels[pixelIdx + 2] / 255.0f;
            size_t rIdx = y * size + x;
            size_t gIdx = size * size + y * size + x;
            size_t bIdx = 2 * size * size + y * size + x;
            inputTensor[rIdx] = r;
            inputTensor[gIdx] = g;
            inputTensor[bIdx] = b;
        }
    }
    free(rawPixels);

    // Step 4: Create memory info and input OrtValue tensor
    OrtMemoryInfo *memInfo = NULL;
    _ort->CreateMemoryInfo("Cpu", OrtArenaAllocator, 0, OrtMemTypeDefault, &memInfo);

    int64_t inputShape[] = {1, 3, size, size};
    OrtValue *inputValue = NULL;
    // CreateTensorWithDataAsOrtValue takes ownership of inputTensor - ORT frees it
    OrtStatus *tensorStatus = _ort->CreateTensorWithDataAsOrtValue(
        memInfo,
        (void *)inputTensor,
        floatCount * sizeof(float),
        inputShape,
        4,
        ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT,
        &inputValue
    );
    if (tensorStatus != NULL) {
        free(inputTensor); // fallback: free ourselves
        if (error) *error = [self errorFromStatus:tensorStatus code:105 msg:@"Failed to create input tensor"];
        return nil;
    }
    // Note: inputTensor is now owned by inputValue - do NOT free it

    // Step 5: Run inference
    const char *inputNames[] = {[self.inputName UTF8String]};
    const char *outputNames[] = {[self.outputName UTF8String]};
    OrtValue *outputValue = NULL;
    OrtStatus *runStatus = _ort->Run(_session, NULL,
                                     inputNames, (const OrtValue**)&inputValue, 1,
                                     outputNames, 1, &outputValue);
    // inputValue is no longer needed after Run
    inputValue = NULL;

    if (runStatus != NULL || !outputValue) {
        if (error) *error = [self errorFromStatus:runStatus code:106 msg:@"ONNX inference failed"];
        return nil;
    }

    // Step 6: Get output shape
    OrtTensorTypeAndShapeInfo *shapeInfo = NULL;
    _ort->GetTensorTypeAndShape(outputValue, &shapeInfo);
    size_t dimCount = 0;
    _ort->GetDimensionsCount(shapeInfo, &dimCount);
    int64_t outShape[4] = {0};
    _ort->GetDimensions(shapeInfo, outShape, dimCount);
    int64_t outH = outShape[2];
    int64_t outW = outShape[3];
    // Note: shapeInfo is owned by outputValue in this ONNX Runtime version, no manual release needed

    // Step 7: Get output tensor data (Float32, range [0, 1])
    void *outputData = NULL;
    _ort->GetTensorMutableData(outputValue, &outputData);

    // Step 8: Convert Float32 [0,1] -> grayscale UIImage
    size_t maskByteCount = outH * outW;
    uint8_t *maskBytes = (uint8_t *)malloc(maskByteCount);
    float *floatData = (float *)outputData;
    for (NSInteger i = 0; i < maskByteCount; i++) {
        float v = floatData[i];
        v = fminf(1.0f, fmaxf(0.0f, v));
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
    const char *statusMsg = _ort->GetErrorMessage(status);
    NSString *msgStr = [NSString stringWithFormat:@"%@: %s", msg, statusMsg ? statusMsg : "unknown"];
    return [NSError errorWithDomain:@"ISNetWrapper" code:code userInfo:@{NSLocalizedDescriptionKey: msgStr}];
}

@end
