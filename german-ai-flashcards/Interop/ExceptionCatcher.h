#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Bridges Objective-C exceptions into Swift-catchable errors. Some system APIs (notably
/// `BGTaskScheduler`) raise an `NSException` for misconfiguration instead of returning an
/// `NSError`, and Swift's `do/catch` cannot catch those — it crashes. Wrap such a call in
/// `runBlock:error:` so an exception becomes a thrown Swift error the caller can recover from.
@interface KBExceptionCatcher : NSObject

/// Runs `block`, returning YES if it completed, or NO (with `error` set) if it raised an exception.
/// Imported into Swift as the throwing `try KBExceptionCatcher.run { ... }`.
+ (BOOL)run:(NS_NOESCAPE void (^)(void))block error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
