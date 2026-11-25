#import "ExceptionCatcher.h"

@implementation KBExceptionCatcher

+ (BOOL)run:(NS_NOESCAPE void (^)(void))block error:(NSError * _Nullable * _Nullable)error {
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        if (error) {
            *error = [NSError errorWithDomain:@"KBExceptionCatcher"
                                         code:0
                                     userInfo:@{ NSLocalizedDescriptionKey: exception.reason ?: exception.name }];
        }
        return NO;
    }
}

@end
