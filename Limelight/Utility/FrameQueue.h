@import Foundation;
@import VideoToolbox;

@class Frame;
@class FloatBuffer;

NS_ASSUME_NONNULL_BEGIN

@interface FrameQueue : NSObject

@property (nonatomic, readonly) NSUInteger count;
@property (nonatomic) FloatBuffer *frameDropMetrics;
@property (nonatomic) int highWaterMark;
@property (nonatomic, readonly) int maxCapacity;

+ (instancetype)sharedInstance;

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;
- (BOOL)isEmpty;
- (void)clear;
- (int)enqueue:(Frame *)frame;
- (int)enqueue:(Frame *)frame withSlackSize:(int)slack;
- (nullable Frame *)dequeue;
- (nullable Frame *)dequeueWithTimeout:(CFTimeInterval)timeout;
- (CFTimeInterval)estimatedFramerate;
- (int)currentSoftCap;
- (void)waitForEnqueue;

@end

NS_ASSUME_NONNULL_END
