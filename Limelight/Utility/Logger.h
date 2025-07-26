//
//  Logger.h
//  Moonlight
//
//  Created by Diego Waxemberg on 2/10/15.
//  Copyright (c) 2015 Moonlight Stream. All rights reserved.
//

@import Foundation;
@import Dispatch;
@import QuartzCore;

typedef enum {
    LOG_D,
    LOG_I,
    LOG_W,
    LOG_E
} LogLevel;

#define PRFX_DEBUG @"<DEBUG>"
#define PRFX_INFO @"<INFO>"
#define PRFX_WARN @"<WARN>"
#define PRFX_ERROR @"<ERROR>"

@interface Logger : NSObject

// Class methods for logging
+ (void)logWithLevel:(LogLevel)level format:(NSString *)format, ... NS_FORMAT_FUNCTION(2,3);
+ (void)logWithLevel:(LogLevel)level tag:(NSString *)tag format:(NSString *)format, ... NS_FORMAT_FUNCTION(3,4);

// Convenience methods for different log levels
+ (void)debug:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);
+ (void)info:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);
+ (void)warn:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);
+ (void)error:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);

+ (void)debugWithTag:(NSString *)tag format:(NSString *)format, ... NS_FORMAT_FUNCTION(2,3);
+ (void)infoWithTag:(NSString *)tag format:(NSString *)format, ... NS_FORMAT_FUNCTION(2,3);
+ (void)warnWithTag:(NSString *)tag format:(NSString *)format, ... NS_FORMAT_FUNCTION(2,3);
+ (void)errorWithTag:(NSString *)tag format:(NSString *)format, ... NS_FORMAT_FUNCTION(2,3);

@end

// Legacy C-style function declarations for backward compatibility
void Log(LogLevel level, NSString* fmt, ...);
void LogTag(LogLevel level, NSString* tag, NSString* fmt, ...);

// LogOnce() is a one-time log message for use in hot areas of the code
#define CONCAT(a,b)   CONCAT2(a,b)
#define CONCAT2(a,b)  a##b

#define LogOnce(level, fmt, ...)                                    \
  do {                                                              \
    static dispatch_once_t CONCAT(_onceToken_, __LINE__);           \
    dispatch_once(&CONCAT(_onceToken_, __LINE__), ^{                \
      Log(level, fmt, ##__VA_ARGS__);                               \
    });                                                             \
  } while (0)

// Disable all logging in release mode for performance
#ifdef DEBUG
    #define Log(level, fmt, ...) \
        LogTag(level, NULL, fmt, ##__VA_ARGS__)
#else
    #define Log(level, fmt, ...) do {} while(0)
#endif

// FrameQueue log helpers FQLog() is a no-op unless FRAME_QUEUE_VERBOSE is defined

static inline NSString *FQQoSString(qos_class_t qos) {
    switch (qos) {
        case QOS_CLASS_USER_INTERACTIVE: return @"UI-25";
        case QOS_CLASS_USER_INITIATED:   return @"IN-19";
        case QOS_CLASS_DEFAULT:          return @"DF-15";
        case QOS_CLASS_UTILITY:          return @"UT-11";
        case QOS_CLASS_BACKGROUND:       return @"BG-09";
        default:                         return [NSString stringWithFormat:@"??-%d", qos];
    }
}

static inline NSString *FQLogPrefix(void) {
    CFTimeInterval now = CACurrentMediaTime();
    NSString *qos = FQQoSString(qos_class_self());
    return [NSString stringWithFormat:@"[%.3f] [%@]", now, qos];
}

#if defined(FRAME_QUEUE_VERBOSE)
  #define FQLog(level, fmt, ...) \
    Log(level, @"%@ " fmt, FQLogPrefix(), ##__VA_ARGS__)
#else
  #define FQLog(level, fmt, ...) do {} while(0)
#endif
