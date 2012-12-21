// AFHTTPClient+ProxyQueue.m
//
// Copyright (c) 2012 James Tang (mystcolor@gmail.com)
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import "AFHTTPClient+ProxyQueue.h"
#import "AFNetworking.h"
#import <objc/runtime.h>

typedef void (^AFCompletionBlock)(void);

@interface AFHTTPClientProxy : NSProxy

@property (nonatomic, strong) NSOperationQueue *operationQueue;
@property (nonatomic, weak)   id target;

+ (AFHTTPClientProxy *)proxyWithTarget:(id)target;

@end


@implementation AFHTTPClientProxy

- (id)init {
    _operationQueue = [[NSOperationQueue alloc] init];
    _operationQueue.maxConcurrentOperationCount = 1;
    return self;
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel {
    return [self.target methodSignatureForSelector:sel];
}

- (void)forwardInvocation:(NSInvocation *)invocation {
    [invocation invokeWithTarget:self.target];
}

- (void)dealloc {
    [self.operationQueue cancelAllOperations];
}

+ (AFHTTPClientProxy *)proxyWithTarget:(id)target {
    AFHTTPClientProxy *proxy = [[AFHTTPClientProxy alloc] init];
    proxy.target = target;
    return proxy;
}

#pragma mark - AFHTTPClient overrides

- (void)enqueueHTTPRequestOperation:(AFHTTPRequestOperation *)operation {
    [self.operationQueue addOperation:operation];
}

- (void)cancelAllHTTPOperationsWithMethod:(NSString *)method
                                     path:(NSString *)path
{
    NSString *URLStringToMatched = [[[self.target requestWithMethod:(method ?: @"GET") path:path parameters:nil] URL] absoluteString];
    
    for (NSOperation *operation in [self.operationQueue operations]) {
        if (![operation isKindOfClass:[AFHTTPRequestOperation class]]) {
            continue;
        }
        
        BOOL hasMatchingMethod = !method || [method isEqualToString:[[(AFHTTPRequestOperation *)operation request] HTTPMethod]];
        BOOL hasMatchingURL = [[[[(AFHTTPRequestOperation *)operation request] URL] absoluteString] isEqualToString:URLStringToMatched];
        
        if (hasMatchingMethod && hasMatchingURL) {
            [operation cancel];
        }
    }
}

- (void)enqueueBatchOfHTTPRequestOperations:(NSArray *)operations
                              progressBlock:(void (^)(NSUInteger numberOfFinishedOperations, NSUInteger totalNumberOfOperations))progressBlock
                            completionBlock:(void (^)(NSArray *operations))completionBlock
{
    __block dispatch_group_t dispatchGroup = dispatch_group_create();
    NSBlockOperation *batchedOperation = [NSBlockOperation blockOperationWithBlock:^{
        dispatch_group_notify(dispatchGroup, dispatch_get_main_queue(), ^{
            if (completionBlock) {
                completionBlock(operations);
            }
        });
#if !OS_OBJECT_USE_OBJC
        dispatch_release(dispatchGroup);
#endif
    }];
    
    for (AFHTTPRequestOperation *operation in operations) {
        AFCompletionBlock originalCompletionBlock = [operation.completionBlock copy];
        operation.completionBlock = ^{
            dispatch_queue_t queue = operation.successCallbackQueue ?: dispatch_get_main_queue();
            dispatch_group_async(dispatchGroup, queue, ^{
                if (originalCompletionBlock) {
                    originalCompletionBlock();
                }
                
                __block NSUInteger numberOfFinishedOperations = 0;
                [operations enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
                    if ([(NSOperation *)obj isFinished]) {
                        numberOfFinishedOperations++;
                    }
                }];
                
                if (progressBlock) {
                    progressBlock(numberOfFinishedOperations, [operations count]);
                }
                
                dispatch_group_leave(dispatchGroup);
            });
        };
        
        dispatch_group_enter(dispatchGroup);
        [batchedOperation addDependency:operation];
    }
    [self.operationQueue addOperations:operations waitUntilFinished:NO];
    [self.operationQueue addOperation:batchedOperation];
}

@end


@interface AFHTTPClient (ProxyQueuePrivate)

@property (nonatomic, strong) NSMutableDictionary *proxiesDict;

@end


@implementation AFHTTPClient (ProxyQueue)

static char *proxiesDictKey;

- (void)setProxiesDict:(NSMutableDictionary *)proxiesDict {
    objc_setAssociatedObject(self, &proxiesDictKey, proxiesDict, OBJC_ASSOCIATION_RETAIN);
}

- (NSMutableDictionary *)proxiesDict {
    return objc_getAssociatedObject(self, &proxiesDictKey);
}

- (AFHTTPClient *)proxyQueueNamed:(NSString *)name {
    if ( ! self.proxiesDict) {
        self.proxiesDict = [NSMutableDictionary dictionary];
    }

    AFHTTPClientProxy *proxy = [self.proxiesDict objectForKey:name];
    if ( ! proxy) {
        proxy = [AFHTTPClientProxy proxyWithTarget:self];
        [self.proxiesDict setObject:proxy forKey:name];
    }
    
    return (AFHTTPClient *)proxy;
}

@end
