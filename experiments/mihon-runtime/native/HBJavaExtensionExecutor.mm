#import "HBJavaExtensionExecutor.h"
#import <dispatch/dispatch.h>
#include <jni.h>
#include <cstdlib>
#include <string>
#include <vector>

extern "C" void loadfunctions(void);

NSErrorDomain const HBJavaExtensionExecutorErrorDomain = @"com.missingems.honbaku.java-executor";
const NSUInteger HBJavaExtensionMaximumRequestUTF16Units = 524288;
const NSUInteger HBJavaExtensionMaximumResponseUTF16Units = 4194304;
const NSUInteger HBJavaExtensionMaximumImageBytes = 32 * 1024 * 1024;
static const NSUInteger HBMaximumPendingJobs = 32;
#if defined(HB_JAVA_RUNTIME_DIAGNOSTICS) && HB_JAVA_RUNTIME_DIAGNOSTICS
static const NSUInteger HBMaximumCleanupCompletions = 32;
typedef void (^HBCleanupCompletion)(NSError *_Nullable);
#endif

static NSError *HBError(HBJavaExtensionExecutorError code, NSString *message) {
    return [NSError errorWithDomain:HBJavaExtensionExecutorErrorDomain code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

/// Exception capture also works when PushLocalFrame itself failed. Every
/// temporary reference created here is explicitly deleted, and any secondary
/// exception from Throwable.toString is cleared before returning to the caller.
static NSError *HBTakeJavaException(JNIEnv *env, NSString *context) {
    jthrowable thrown = env->ExceptionOccurred();
    if (!thrown) return nil;
    env->ExceptionClear();
    NSString *detail = @"Java operation failed";
    jclass type = env->GetObjectClass(thrown);
    jmethodID method = type ? env->GetMethodID(type, "toString", "()Ljava/lang/String;") : nullptr;
    jstring text = method && !env->ExceptionCheck()
        ? (jstring)env->CallObjectMethod(thrown, method) : nullptr;
    if (text && !env->ExceptionCheck()) {
        jsize length = env->GetStringLength(text);
        const jchar *characters = env->GetStringChars(text, nullptr);
        if (characters) {
            detail = [[NSString alloc] initWithCharacters:(const unichar *)characters
                                                   length:(NSUInteger)MIN(length, 4096)];
            env->ReleaseStringChars(text, characters);
        }
    }
    env->ExceptionClear();
    if (text) env->DeleteLocalRef(text);
    if (type) env->DeleteLocalRef(type);
    env->DeleteLocalRef(thrown);
    return HBError(HBJavaExtensionExecutorJavaException,
                   [NSString stringWithFormat:@"%@: %@", context, detail]);
}

struct HBLocalFrame {
    JNIEnv *env;
    bool active;
    explicit HBLocalFrame(JNIEnv *environment, jint capacity = 64)
        : env(environment), active(environment->PushLocalFrame(capacity) == JNI_OK) {}
    ~HBLocalFrame() { if (active) env->PopLocalFrame(nullptr); }
};

static jstring HBNewJavaString(JNIEnv *env, NSString *text, NSError **error) {
    NSUInteger length = text.length;
    if (length > HBJavaExtensionMaximumRequestUTF16Units) {
        *error = HBError(HBJavaExtensionExecutorRequestTooLarge, @"The Java request is too large.");
        return nullptr;
    }
    // NewString uses UTF-16, preserving supplementary characters and avoiding
    // modified-UTF-8's different handling of NUL and surrogate pairs.
    jchar *characters = length ? (jchar *)malloc(length * sizeof(jchar)) : nullptr;
    if (length && !characters) {
        *error = HBError(HBJavaExtensionExecutorUnavailable, @"Unable to allocate the Java request.");
        return nullptr;
    }
    if (length) [text getCharacters:(unichar *)characters range:NSMakeRange(0, length)];
    jstring result = env->NewString(characters, (jsize)length);
    free(characters);
    if (NSError *exception = HBTakeJavaException(env, @"Creating the Java request")) *error = exception;
    else if (!result) *error = HBError(HBJavaExtensionExecutorUnavailable, @"Unable to create the Java request.");
    return result;
}

static NSString *HBCopyJavaString(JNIEnv *env, jstring value, NSUInteger limit, NSError **error) {
    if (!value) {
        *error = HBError(HBJavaExtensionExecutorInvalidResponse, @"The Java bridge returned no text.");
        return nil;
    }
    jsize length = env->GetStringLength(value);
    if ((NSUInteger)length > limit) {
        *error = HBError(HBJavaExtensionExecutorResponseTooLarge, @"The Java response is too large.");
        return nil;
    }
    const jchar *characters = env->GetStringChars(value, nullptr);
    if (!characters) {
        *error = HBTakeJavaException(env, @"Reading the Java response") ?:
            HBError(HBJavaExtensionExecutorUnavailable, @"Unable to read the Java response.");
        return nil;
    }
    NSString *result = [[NSString alloc] initWithCharacters:(const unichar *)characters
                                                    length:(NSUInteger)length];
    env->ReleaseStringChars(value, characters);
    return result;
}

static BOOL HBIsJSONObject(NSString *text) {
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) return NO;
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    return [object isKindOfClass:NSDictionary.class];
}

@interface HBJavaImagePayload ()
- (instancetype)initWithData:(NSData *)data mediaType:(NSString *)mediaType sha256:(NSString *)sha256;
@end

@implementation HBJavaImagePayload
- (instancetype)initWithData:(NSData *)data mediaType:(NSString *)mediaType sha256:(NSString *)sha256 {
    self = [super init];
    if (self) {
        _data = [data copy];
        _mediaType = [mediaType copy];
        _sha256 = [sha256 copy];
    }
    return self;
}
@end

@interface HBJavaExtensionExecutor ()
- (instancetype)initPrivate;
- (void)workerMain;
- (BOOL)enqueue:(dispatch_block_t)job;
- (BOOL)prepareVM:(NSError **)error;
- (NSError *)validateRequest:(NSString *)request;
- (BOOL)prepareImageMethod:(NSError **)error;
@end

@implementation HBJavaExtensionExecutor {
    NSCondition *_condition;
    NSMutableArray<dispatch_block_t> *_jobs;
    NSThread *_worker;
    BOOL _startupAttempted;
    NSError *_startupFailure;
    JavaVM *_vm;
    JNIEnv *_environment;
    jclass _bridgeClass;
    jmethodID _executeMethod;
    jmethodID _imageMethod;
    jclass _imageResultClass;
    jfieldID _imageDataField;
    jfieldID _imageMediaTypeField;
    jfieldID _imageSHA256Field;
#if defined(HB_JAVA_RUNTIME_DIAGNOSTICS) && HB_JAVA_RUNTIME_DIAGNOSTICS
    dispatch_block_t _reservedCleanupJob;
    NSMutableArray<HBCleanupCompletion> *_cleanupCompletions;
    BOOL _cleanupPending;
#endif
}

+ (instancetype)sharedExecutor {
    static HBJavaExtensionExecutor *executor;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ executor = [[self alloc] initPrivate]; });
    return executor;
}

- (instancetype)initPrivate {
    self = [super init];
    if (self) {
        _condition = [NSCondition new];
        _jobs = [NSMutableArray new];
#if defined(HB_JAVA_RUNTIME_DIAGNOSTICS) && HB_JAVA_RUNTIME_DIAGNOSTICS
        _cleanupCompletions = [NSMutableArray new];
#endif
        _worker = [[NSThread alloc] initWithTarget:self selector:@selector(workerMain) object:nil];
        _worker.name = @"Honbako Java Extensions";
        _worker.stackSize = 8 * 1024 * 1024;
        _worker.qualityOfService = NSQualityOfServiceUserInitiated;
        [_worker start];
    }
    return self;
}

- (void)workerMain {
    // The creating thread owns the JNIEnv for the lifetime of the process.
    // This is deliberately not a dispatch queue whose blocks can change OS
    // threads. No DestroyJavaVM or thread-detach occurs between requests.
    for (;;) {
        @autoreleasepool {
            [_condition lock];
            while (_jobs.count == 0) [_condition wait];
            dispatch_block_t first = _jobs.firstObject;
#if defined(HB_JAVA_RUNTIME_DIAGNOSTICS) && HB_JAVA_RUNTIME_DIAGNOSTICS
            if (first == _reservedCleanupJob) _reservedCleanupJob = nil;
#endif
            dispatch_block_t job = [first copy];
            [_jobs removeObjectAtIndex:0];
            [_condition unlock];
            job();
        }
    }
}

- (BOOL)enqueue:(dispatch_block_t)job {
    [_condition lock];
    NSUInteger reserved = 0;
#if defined(HB_JAVA_RUNTIME_DIAGNOSTICS) && HB_JAVA_RUNTIME_DIAGNOSTICS
    reserved = _reservedCleanupJob ? 1 : 0;
#endif
    if (_jobs.count - reserved >= HBMaximumPendingJobs) {
        [_condition unlock];
        return NO;
    }
    [_jobs addObject:[job copy]];
    [_condition signal];
    [_condition unlock];
    return YES;
}

- (BOOL)prepareVM:(NSError **)error {
    NSAssert(NSThread.currentThread == _worker, @"JNI must stay on its owning thread");
    if (_startupAttempted) {
        if (_startupFailure) *error = _startupFailure;
        return _startupFailure == nil;
    }
    _startupAttempted = YES;
    NSURL *resources = NSBundle.mainBundle.resourceURL;
    NSFileManager *files = NSFileManager.defaultManager;
    NSMutableArray<NSString *> *classpath = [NSMutableArray new];
    NSArray<NSString *> *jars = @[@"honbako-extension-bridge.jar", @"komga-proof-dependencies.jar"];
#if defined(HB_JAVA_RUNTIME_DIAGNOSTICS) && HB_JAVA_RUNTIME_DIAGNOSTICS
    jars = [jars arrayByAddingObject:@"RuntimeProbe.jar"];
#endif
    NSMutableArray<NSString *> *required = [jars mutableCopy];
    [required addObject:@"lib/lib/modules"];
    for (NSString *name in required) {
        NSURL *url = [resources URLByAppendingPathComponent:name];
        NSNumber *regular = nil;
        if (!url.isFileURL || ![url getResourceValue:&regular forKey:NSURLIsRegularFileKey error:NULL]
                || !regular.boolValue || ![files isReadableFileAtPath:url.path]) {
            _startupFailure = HBError(HBJavaExtensionExecutorMissingResource,
                                      [NSString stringWithFormat:@"Missing bundled Java resource: %@", name]);
            *error = _startupFailure;
            return NO;
        }
        if ([jars containsObject:name]) {
            if ([url.path containsString:@":"]) {
                _startupFailure = HBError(HBJavaExtensionExecutorMissingResource, @"Invalid bundled Java resource path.");
                *error = _startupFailure;
                return NO;
            }
            [classpath addObject:url.path];
        }
    }
    JavaVM *existing = nullptr;
    jsize count = 0;
    jint query = JNI_GetCreatedJavaVMs(&existing, 1, &count);
    if (query != JNI_OK || count != 0) {
        _startupFailure = HBError(HBJavaExtensionExecutorStartupFailed,
                                  @"A Java VM already exists or its ownership could not be verified.");
        *error = _startupFailure;
        return NO;
    }
    NSString *classpathText = [classpath componentsJoinedByString:@":"];
    std::vector<std::string> arguments = {
        std::string("-Djava.class.path=") + classpathText.UTF8String,
        std::string("-Djava.io.tmpdir=") + NSTemporaryDirectory().UTF8String,
        "-Xms16m", "-Xmx128m", "--add-modules=java.logging,java.xml",
        "-Djdk.system.module.finder.disableFastPath=true"
    };
#if defined(HB_JAVA_RUNTIME_DIAGNOSTICS) && HB_JAVA_RUNTIME_DIAGNOSTICS
    arguments.push_back("-Dhonbako.probe.keepFixture=true");
#endif
    std::vector<JavaVMOption> options(arguments.size());
    for (size_t index = 0; index < arguments.size(); ++index) options[index].optionString = arguments[index].data();
    JavaVMInitArgs settings = {};
    settings.version = JNI_VERSION_1_8;
    settings.nOptions = (jint)options.size();
    settings.options = options.data();
    settings.ignoreUnrecognized = JNI_FALSE;
    loadfunctions();
    jint status = JNI_CreateJavaVM(&_vm, (void **)&_environment, &settings);
    if (status != JNI_OK || !_environment) {
        _startupFailure = HBError(HBJavaExtensionExecutorStartupFailed,
                                  [NSString stringWithFormat:@"Java VM startup failed (%d).", status]);
        *error = _startupFailure;
        return NO;
    }
    HBLocalFrame frame(_environment);
    if (!frame.active) {
        _startupFailure = HBTakeJavaException(_environment, @"Preparing the Java bridge") ?:
            HBError(HBJavaExtensionExecutorStartupFailed, @"Unable to prepare the Java bridge.");
        *error = _startupFailure;
        return NO;
    }
    jclass bridge = _environment->FindClass("com/missingems/honbako/runtime/ExtensionBridge");
    if (bridge && !_environment->ExceptionCheck()) {
        _executeMethod = _environment->GetStaticMethodID(bridge, "execute", "(Ljava/lang/String;)Ljava/lang/String;");
        if (_executeMethod && !_environment->ExceptionCheck()) _bridgeClass = (jclass)_environment->NewGlobalRef(bridge);
    }
    _startupFailure = HBTakeJavaException(_environment, @"Loading the Java bridge");
    if (!_startupFailure && (!_bridgeClass || !_executeMethod)) {
        _startupFailure = HBError(HBJavaExtensionExecutorStartupFailed, @"The bundled Java bridge is unavailable.");
    }
    if (_startupFailure) *error = _startupFailure;
    return _startupFailure == nil;
}

- (NSError *)validateRequest:(NSString *)request {
    if (![request isKindOfClass:NSString.class] || request.length == 0) {
        return HBError(HBJavaExtensionExecutorInvalidRequest, @"Provide a JSON object for the Java request.");
    }
    if (request.length > HBJavaExtensionMaximumRequestUTF16Units) {
        return HBError(HBJavaExtensionExecutorRequestTooLarge, @"The Java request is too large.");
    }
    return nil;
}

- (void)executeJSON:(NSString *)requestJSON
         completion:(void (^)(NSString *_Nullable, NSError *_Nullable))completion {
    if (!completion) return;
    NSError *invalid = [self validateRequest:requestJSON];
    if (invalid) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, invalid); });
        return;
    }
    NSString *request = [requestJSON copy];
    BOOL queued = [self enqueue:^{
        NSError *error = nil;
        NSString *response = nil;
        if (!HBIsJSONObject(request)) error = HBError(HBJavaExtensionExecutorInvalidRequest, @"The Java request must be a JSON object.");
        else if ([self prepareVM:&error]) {
            HBLocalFrame frame(self->_environment);
            if (!frame.active) error = HBTakeJavaException(self->_environment, @"Preparing a Java request") ?:
                HBError(HBJavaExtensionExecutorUnavailable, @"Unable to prepare a Java request.");
            else {
                jstring input = HBNewJavaString(self->_environment, request, &error);
                if (input && !error) {
                    jstring output = (jstring)self->_environment->CallStaticObjectMethod(self->_bridgeClass, self->_executeMethod, input);
                    error = HBTakeJavaException(self->_environment, @"Executing the Java request");
                    if (!error) response = HBCopyJavaString(self->_environment, output, HBJavaExtensionMaximumResponseUTF16Units, &error);
                    if (response && !HBIsJSONObject(response)) {
                        response = nil;
                        error = HBError(HBJavaExtensionExecutorInvalidResponse, @"The Java bridge returned invalid JSON.");
                    }
                }
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(response, error); });
    }];
    if (!queued) dispatch_async(dispatch_get_main_queue(), ^{
        completion(nil, HBError(HBJavaExtensionExecutorQueueFull, @"The Java request queue is full."));
    });
}

- (BOOL)prepareImageMethod:(NSError **)error {
    if (_imageMethod && _imageResultClass && _imageDataField && _imageMediaTypeField && _imageSHA256Field) return YES;
    _imageMethod = _environment->GetStaticMethodID(_bridgeClass, "image",
        "(Ljava/lang/String;)Lcom/missingems/honbako/runtime/ExtensionBridge$ImageResult;");
    jclass type = !_environment->ExceptionCheck()
        ? _environment->FindClass("com/missingems/honbako/runtime/ExtensionBridge$ImageResult") : nullptr;
    if (type && !_environment->ExceptionCheck()) {
        _imageDataField = _environment->GetFieldID(type, "data", "[B");
        if (!_environment->ExceptionCheck()) _imageMediaTypeField = _environment->GetFieldID(type, "mediaType", "Ljava/lang/String;");
        if (!_environment->ExceptionCheck()) _imageSHA256Field = _environment->GetFieldID(type, "sha256", "Ljava/lang/String;");
        if (!_environment->ExceptionCheck()) _imageResultClass = (jclass)_environment->NewGlobalRef(type);
    }
    *error = HBTakeJavaException(_environment, @"Loading the binary image bridge");
    if (!*error && (!_imageMethod || !_imageResultClass)) *error = HBError(HBJavaExtensionExecutorUnavailable, @"The binary image bridge is unavailable.");
    return *error == nil;
}

- (void)imageJSON:(NSString *)requestJSON
       completion:(void (^)(HBJavaImagePayload *_Nullable, NSError *_Nullable))completion {
    if (!completion) return;
    NSError *invalid = [self validateRequest:requestJSON];
    if (invalid) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, invalid); });
        return;
    }
    NSString *request = [requestJSON copy];
    BOOL queued = [self enqueue:^{
        NSError *error = nil;
        HBJavaImagePayload *payload = nil;
        if (!HBIsJSONObject(request)) error = HBError(HBJavaExtensionExecutorInvalidRequest, @"The image request must be a JSON object.");
        else if ([self prepareVM:&error]) {
            HBLocalFrame frame(self->_environment);
            if (!frame.active) error = HBTakeJavaException(self->_environment, @"Preparing an image request") ?:
                HBError(HBJavaExtensionExecutorUnavailable, @"Unable to prepare an image request.");
            else if ([self prepareImageMethod:&error]) {
                jstring input = HBNewJavaString(self->_environment, request, &error);
                if (input && !error) {
                    jobject result = self->_environment->CallStaticObjectMethod(self->_bridgeClass, self->_imageMethod, input);
                    error = HBTakeJavaException(self->_environment, @"Loading the image");
                    if (!error && !result) error = HBError(HBJavaExtensionExecutorInvalidResponse, @"The Java bridge returned no image.");
                    if (!error) {
                        jbyteArray bytes = (jbyteArray)self->_environment->GetObjectField(result, self->_imageDataField);
                        jstring type = (jstring)self->_environment->GetObjectField(result, self->_imageMediaTypeField);
                        jstring hash = (jstring)self->_environment->GetObjectField(result, self->_imageSHA256Field);
                        error = HBTakeJavaException(self->_environment, @"Reading the image result");
                        if (!error && !bytes) error = HBError(HBJavaExtensionExecutorInvalidResponse, @"The Java bridge returned no image bytes.");
                        if (!error) {
                            jsize length = self->_environment->GetArrayLength(bytes);
                            if (length <= 0 || (NSUInteger)length > HBJavaExtensionMaximumImageBytes) {
                                error = HBError(HBJavaExtensionExecutorResponseTooLarge, @"The image is empty or too large.");
                            } else {
                                NSString *mediaType = type ? HBCopyJavaString(self->_environment, type, 256, &error) : nil;
                                NSString *sha256 = !error && hash ? HBCopyJavaString(self->_environment, hash, 128, &error) : nil;
                                void *buffer = !error ? malloc((size_t)length) : nullptr;
                                if (!error && !buffer) error = HBError(HBJavaExtensionExecutorUnavailable, @"Unable to allocate the image.");
                                if (!error) {
                                    self->_environment->GetByteArrayRegion(bytes, 0, length, (jbyte *)buffer);
                                    error = HBTakeJavaException(self->_environment, @"Copying the image");
                                    if (!error) {
                                        NSData *data = [NSData dataWithBytesNoCopy:buffer length:(NSUInteger)length freeWhenDone:YES];
                                        buffer = nullptr;
                                        payload = [[HBJavaImagePayload alloc] initWithData:data mediaType:mediaType sha256:sha256];
                                    }
                                }
                                free(buffer);
                            }
                        }
                    }
                }
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(payload, error); });
    }];
    if (!queued) dispatch_async(dispatch_get_main_queue(), ^{
        completion(nil, HBError(HBJavaExtensionExecutorQueueFull, @"The Java request queue is full."));
    });
}

#if defined(HB_JAVA_RUNTIME_DIAGNOSTICS) && HB_JAVA_RUNTIME_DIAGNOSTICS
- (void)runBundledProofWithCompletion:(void (^)(NSString *_Nullable, NSString *_Nullable, NSError *_Nullable))completion {
    if (!completion) return;
    BOOL queued = [self enqueue:^{
        NSError *error = nil;
        NSString *core = nil;
        NSString *proof = nil;
        if ([self prepareVM:&error]) {
            HBLocalFrame frame(self->_environment);
            if (!frame.active) error = HBTakeJavaException(self->_environment, @"Preparing the runtime diagnostic") ?:
                HBError(HBJavaExtensionExecutorUnavailable, @"Unable to prepare the runtime diagnostic.");
            else {
                jclass coreClass = self->_environment->FindClass("com/missingems/honbako/runtime/RuntimeProbe");
                jmethodID coreRun = coreClass && !self->_environment->ExceptionCheck()
                    ? self->_environment->GetStaticMethodID(coreClass, "run", "()Ljava/lang/String;") : nullptr;
                jstring coreValue = coreRun && !self->_environment->ExceptionCheck()
                    ? (jstring)self->_environment->CallStaticObjectMethod(coreClass, coreRun) : nullptr;
                error = HBTakeJavaException(self->_environment, @"Running the core diagnostic");
                if (!error) core = HBCopyJavaString(self->_environment, coreValue, 65536, &error);
                if (!error) {
                    jclass proofClass = self->_environment->FindClass("com/missingems/honbako/runtime/KomgaDeviceProbe");
                    jmethodID proofRun = proofClass && !self->_environment->ExceptionCheck()
                        ? self->_environment->GetStaticMethodID(proofClass, "run", "(Ljava/lang/String;)Ljava/lang/String;") : nullptr;
                    jstring root = !self->_environment->ExceptionCheck()
                        ? HBNewJavaString(self->_environment, NSBundle.mainBundle.resourcePath, &error) : nullptr;
                    jstring proofValue = proofRun && root && !error && !self->_environment->ExceptionCheck()
                        ? (jstring)self->_environment->CallStaticObjectMethod(proofClass, proofRun, root) : nullptr;
                    NSError *exception = HBTakeJavaException(self->_environment, @"Running the extension diagnostic");
                    if (exception) error = exception;
                    if (!error) proof = HBCopyJavaString(self->_environment, proofValue, HBJavaExtensionMaximumResponseUTF16Units, &error);
                }
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{ completion(core, proof, error); });
    }];
    if (!queued) dispatch_async(dispatch_get_main_queue(), ^{
        completion(nil, nil, HBError(HBJavaExtensionExecutorQueueFull, @"The Java request queue is full."));
    });
}

- (void)endBundledProofWithCompletion:(void (^)(NSError *_Nullable))completion {
    if (!completion) return;
    [_condition lock];
    if (_cleanupCompletions.count >= HBMaximumCleanupCompletions) {
        [_condition unlock];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(HBError(HBJavaExtensionExecutorQueueFull, @"Too many diagnostic cleanup requests."));
        });
        return;
    }
    [_cleanupCompletions addObject:[completion copy]];
    if (_cleanupPending) {
        [_condition unlock];
        return;
    }
    _cleanupPending = YES;
    // One reserved slot cannot be consumed by ordinary requests. Keeping this
    // block in the same FIFO also lets earlier requests finish before closing.
    _reservedCleanupJob = [^{
        NSError *error = nil;
        if (self->_startupAttempted && [self prepareVM:&error]) {
            HBLocalFrame frame(self->_environment);
            if (!frame.active) error = HBTakeJavaException(self->_environment, @"Preparing diagnostic cleanup") ?:
                HBError(HBJavaExtensionExecutorUnavailable, @"Unable to prepare diagnostic cleanup.");
            else {
                jclass type = self->_environment->FindClass("com/missingems/honbako/runtime/KomgaDeviceProbe");
                jmethodID close = type && !self->_environment->ExceptionCheck()
                    ? self->_environment->GetStaticMethodID(type, "closeRetainedFixture", "()V") : nullptr;
                if (close && !self->_environment->ExceptionCheck()) self->_environment->CallStaticVoidMethod(type, close);
                error = HBTakeJavaException(self->_environment, @"Closing the diagnostic fixture");
                if (!error && !close) error = HBError(HBJavaExtensionExecutorUnavailable, @"Diagnostic cleanup is unavailable.");
            }
        }
        [self->_condition lock];
        NSArray<HBCleanupCompletion> *completions = [self->_cleanupCompletions copy];
        [self->_cleanupCompletions removeAllObjects];
        self->_cleanupPending = NO;
        [self->_condition unlock];
        dispatch_async(dispatch_get_main_queue(), ^{
            for (HBCleanupCompletion callback in completions) callback(error);
        });
    } copy];
    [_jobs addObject:_reservedCleanupJob];
    [_condition signal];
    [_condition unlock];
}
#endif
@end
