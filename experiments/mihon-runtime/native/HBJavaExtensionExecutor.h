#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const HBJavaExtensionExecutorErrorDomain;
FOUNDATION_EXPORT const NSUInteger HBJavaExtensionMaximumRequestUTF16Units;
FOUNDATION_EXPORT const NSUInteger HBJavaExtensionMaximumResponseUTF16Units;
FOUNDATION_EXPORT const NSUInteger HBJavaExtensionMaximumImageBytes;

typedef NS_ERROR_ENUM(HBJavaExtensionExecutorErrorDomain, HBJavaExtensionExecutorError) {
    HBJavaExtensionExecutorInvalidRequest = 1,
    HBJavaExtensionExecutorRequestTooLarge,
    HBJavaExtensionExecutorQueueFull,
    HBJavaExtensionExecutorMissingResource,
    HBJavaExtensionExecutorStartupFailed,
    HBJavaExtensionExecutorJavaException,
    HBJavaExtensionExecutorInvalidResponse,
    HBJavaExtensionExecutorResponseTooLarge,
    HBJavaExtensionExecutorUnavailable,
};

NS_SWIFT_NAME(JavaImagePayload)
@interface HBJavaImagePayload : NSObject
@property(nonatomic, readonly, copy) NSData *data;
@property(nonatomic, readonly, copy, nullable) NSString *mediaType;
@property(nonatomic, readonly, copy, nullable) NSString *sha256;
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
@end

/// Experimental in-process Java bridge. One VM and one serial worker per process.
/// All completions run asynchronously on the main queue. This object has no UI
/// behavior, does not configure the idle timer, and never destroys the VM.
NS_SWIFT_NAME(JavaExtensionExecutor)
@interface HBJavaExtensionExecutor : NSObject
+ (instancetype)sharedExecutor NS_SWIFT_NAME(sharedExecutor());
- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

/// Accepts a JSON object encoded as text; invokes only ExtensionBridge.execute.
/// Limits are UTF-16 code units and are checked before allocating JNI strings.
- (void)executeJSON:(NSString *)requestJSON
         completion:(void (^)(NSString *_Nullable responseJSON, NSError *_Nullable error))completion
    NS_SWIFT_NAME(execute(json:completion:));

/// Calls the fixed binary image entry point. No base64 conversion is performed.
/// Java byte-array length is checked before allocating the returned NSData.
- (void)imageJSON:(NSString *)requestJSON
       completion:(void (^)(HBJavaImagePayload *_Nullable payload, NSError *_Nullable error))completion
    NS_SWIFT_NAME(image(json:completion:));

#if defined(HB_JAVA_RUNTIME_DIAGNOSTICS) && HB_JAVA_RUNTIME_DIAGNOSTICS
/// Isolated probe only: runs the fixed bundled core and original-content proof.
/// The diagnostic flag also adds RuntimeProbe.jar to the fixed class path.
- (void)runBundledProofWithCompletion:(void (^)(NSString *_Nullable coreResult,
                                               NSString *_Nullable proofJSON,
                                               NSError *_Nullable error))completion
    NS_SWIFT_NAME(runBundledProof(completion:));
/// Releases the opt-in retained fixture after diagnostic JSON/image checks.
- (void)endBundledProofWithCompletion:(void (^)(NSError *_Nullable error))completion
    NS_SWIFT_NAME(endBundledProof(completion:));
#endif
@end

NS_ASSUME_NONNULL_END
