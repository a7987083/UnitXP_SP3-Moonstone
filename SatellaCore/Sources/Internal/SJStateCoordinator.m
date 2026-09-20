#import "SJStateCoordinator.h"
#import "../Public/SJConfiguration.h"
#import <dispatch/dispatch.h>

@implementation SJStateCoordinator

+ (instancetype)shared {
    static SJStateCoordinator *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [[self alloc] initPrivate]; });
    return instance;
}

- (instancetype)init { return [SJStateCoordinator shared]; }

- (instancetype)initPrivate {
    self = [super init];
    if (self) {
        _configuration = [SJConfiguration defaultConfiguration];
        _products = [NSMutableDictionary dictionary];
        _productOrder = [NSMutableArray array];
        _productDelegates = [NSMutableArray array];
        _transactionObservers = [NSMutableArray array];
        _seenTransactions = [NSHashTable hashTableWithOptions:NSPointerFunctionsStrongMemory | NSPointerFunctionsObjectPointerPersonality];
        _diagnostics = [NSMutableArray array];
    }
    return self;
}

- (void)resetSessionStateKeepingConfiguration:(BOOL)keepConfiguration {
    @synchronized (self) {
        if (!keepConfiguration) self.configuration = [SJConfiguration defaultConfiguration];
        [self.products removeAllObjects];
        [self.productOrder removeAllObjects];
        [self.productDelegates removeAllObjects];
        [self.transactionObservers removeAllObjects];
        [self.seenTransactions removeAllObjects];
        [self.diagnostics removeAllObjects];
    }
}

@end
