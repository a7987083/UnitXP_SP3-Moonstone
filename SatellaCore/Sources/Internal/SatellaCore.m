#import "../Public/SatellaCore.h"
#import "SJDiagnostics.h"
#import "SJStateCoordinator.h"

NSString * const SJCoreErrorDomain = @"SatellaCore";
NSNotificationName const SJCoreStateDidChangeNotification = @"SJCoreStateDidChangeNotification";
NSNotificationName const SJCoreConfigurationDidChangeNotification = @"SJCoreConfigurationDidChangeNotification";

@implementation SatellaCore

static NSError *SJCoreMakeError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:SJCoreErrorDomain code:code userInfo:@{NSLocalizedDescriptionKey: message ?: @"Unknown error"}];
}

static BOOL SJFeatureIsValid(SJFeature feature) { return feature >= SJFeatureProductCatalogFallback && feature <= SJFeatureStealthSimulation; }

static void SJPostStateChanged(NSDictionary<NSString *, id> *configurationSnapshot) {
    NSDictionary *snapshot = [configurationSnapshot copy] ?: @{};
    [[NSNotificationCenter defaultCenter] postNotificationName:SJCoreConfigurationDidChangeNotification
                                                        object:nil
                                                      userInfo:@{@"configuration": snapshot}];
    [[NSNotificationCenter defaultCenter] postNotificationName:SJCoreStateDidChangeNotification object:nil];
}

+ (NSString *)version { return @"1.3.0-result-parity"; }

+ (NSDictionary<NSString *,id> *)capabilities {
    return @{
        @"productsDelegateParity": @YES,
        @"invalidProductIdentifierParity": @YES,
        @"productIdentityParity": @YES,
        @"upstreamParityMode": @YES,
        @"transactionObserverParity": @YES,
        @"canMakePaymentsSimulation": @YES,
        @"priceOverrideSimulation": @YES,
        @"transactionPropertySimulation": @YES,
        @"transactionDynamicGetterParity": @YES,
        @"oldReceiptModel": @YES,
        @"receiptResponseModel": @YES,
        @"upstreamReceiptPayloadParity": @YES,
        @"verifyReceiptDecisionLogic": @YES,
        @"disabledMeansPassThrough": @YES,
        @"preferencesCompatibility": @YES,
        @"liveStoreKitInterception": @NO,
        @"dyldConcealmentSimulation": @YES,
        @"dyldConcealment": @NO,
        @"ui": @NO,
        @"constructor": @NO,
        @"swiftRuntime": @NO,
        @"jinx": @NO,
    };
}

+ (SJConfiguration *)configuration { SJStateCoordinator *state=[SJStateCoordinator shared]; @synchronized(state){ return [state.configuration copy]; } }

+ (BOOL)validateConfiguration:(SJConfiguration *)configuration error:(NSError **)error {
    if(![configuration isKindOfClass:SJConfiguration.class]){ if(error)*error=SJCoreMakeError(SJCoreErrorInvalidConfiguration,@"Configuration must be an SJConfiguration instance."); return NO; }
    if(configuration.behaviorMode < SJBehaviorModeUpstreamParity || configuration.behaviorMode > SJBehaviorModeExtendedTesting){ if(error)*error=SJCoreMakeError(SJCoreErrorInvalidConfiguration,@"Unknown behavior mode."); return NO; }
    if(!configuration.testPrice || [configuration.testPrice isEqualToNumber:NSDecimalNumber.notANumber] || [configuration.testPrice compare:NSDecimalNumber.zero]==NSOrderedAscending){ if(error)*error=SJCoreMakeError(SJCoreErrorInvalidConfiguration,@"Test price must be a non-negative decimal number."); return NO; }
    if(configuration.testEnvironment.length==0){ if(error)*error=SJCoreMakeError(SJCoreErrorInvalidConfiguration,@"Test environment must not be empty."); return NO; }
    return YES;
}

+ (BOOL)applyConfiguration:(SJConfiguration *)configuration error:(NSError **)error {
    if(error)*error=nil;
    if(![self validateConfiguration:configuration error:error]) return NO;
    SJStateCoordinator *state=[SJStateCoordinator shared];
    NSDictionary *snapshot;
    @synchronized(state){
        state.configuration=[configuration copy];
        snapshot=[[state.configuration dictionaryRepresentation] copy];
    }
    [SJDiagnostics appendModule:@"Core" message:@"Configuration applied." code:0];
    SJPostStateChanged(snapshot);
    return YES;
}

+ (BOOL)setFeature:(SJFeature)feature enabled:(BOOL)enabled error:(NSError **)error {
    if(error)*error=nil;
    if(!SJFeatureIsValid(feature)){ if(error)*error=SJCoreMakeError(SJCoreErrorInvalidFeature,@"Unknown feature identifier."); return NO; }
    SJStateCoordinator *state=[SJStateCoordinator shared];
    NSDictionary *snapshot;
    @synchronized(state){
        switch(feature){
            case SJFeatureProductCatalogFallback: state.configuration.productCatalogFallbackEnabled=enabled; break;
            case SJFeatureTransactionSimulation: state.configuration.transactionSimulationEnabled=enabled; break;
            case SJFeatureReceiptSimulation: state.configuration.receiptSimulationEnabled=enabled; break;
            case SJFeatureCanMakePaymentsOverride: state.configuration.canMakePaymentsOverrideEnabled=enabled; break;
            case SJFeaturePriceOverride: state.configuration.priceOverrideEnabled=enabled; break;
            case SJFeatureObserverBridge: state.configuration.observerBridgeEnabled=enabled; break;
            case SJFeatureStealthSimulation: state.configuration.stealthPreferenceEnabled=enabled; break;
        }
        snapshot=[[state.configuration dictionaryRepresentation] copy];
    }
    [SJDiagnostics appendModule:@"Core" message:[NSString stringWithFormat:@"Feature %ld set to %@.",(long)feature,enabled?@"enabled":@"disabled"] code:0];
    SJPostStateChanged(snapshot);
    return YES;
}

+ (BOOL)isFeatureEnabled:(SJFeature)feature {
    if(!SJFeatureIsValid(feature)) return NO;
    SJStateCoordinator *state=[SJStateCoordinator shared];
    @synchronized(state){
        switch(feature){
            case SJFeatureProductCatalogFallback:return state.configuration.productCatalogFallbackEnabled;
            case SJFeatureTransactionSimulation:return state.configuration.transactionSimulationEnabled;
            case SJFeatureReceiptSimulation:return state.configuration.receiptSimulationEnabled;
            case SJFeatureCanMakePaymentsOverride:return state.configuration.canMakePaymentsOverrideEnabled;
            case SJFeaturePriceOverride:return state.configuration.priceOverrideEnabled;
            case SJFeatureObserverBridge:return state.configuration.observerBridgeEnabled;
            case SJFeatureStealthSimulation:return state.configuration.stealthPreferenceEnabled;
        }
    }
    return NO;
}
+ (BOOL)isFeatureAvailable:(SJFeature)feature { return SJFeatureIsValid(feature); }
+ (SJFeatureState)stateForFeature:(SJFeature)feature { if(![self isFeatureAvailable:feature])return SJFeatureStateUnavailable; return [self isFeatureEnabled:feature]?SJFeatureStateEnabled:SJFeatureStateDisabled; }

+ (NSDictionary<NSString *,id> *)status {
    SJStateCoordinator *state=[SJStateCoordinator shared];
    NSDictionary *configuration; NSUInteger productCount,delegateCount,observerCount,seenCount,diagnosticCount;
    @synchronized(state){
        configuration=[[state.configuration dictionaryRepresentation] copy];
        productCount=state.products.count;
        delegateCount=state.productDelegates.count;
        observerCount=state.transactionObservers.count;
        seenCount=state.seenTransactions.count;
        diagnosticCount=state.diagnostics.count;
    }
    return @{@"version":[self version],@"capabilities":[self capabilities],@"configuration":configuration,@"mockProductCount":@(productCount),@"productDelegateCount":@(delegateCount),@"transactionObserverCount":@(observerCount),@"seenTransactionCount":@(seenCount),@"diagnosticCount":@(diagnosticCount)};
}

+ (NSData * _Nullable)statusJSONWithError:(NSError **)error { if(error)*error=nil; NSDictionary *status=[self status]; if(![NSJSONSerialization isValidJSONObject:status]){if(error)*error=SJCoreMakeError(SJCoreErrorInvalidConfiguration,@"Status dictionary is not JSON serializable."); return nil;} return [NSJSONSerialization dataWithJSONObject:status options:NSJSONWritingPrettyPrinted error:error]; }
+ (NSArray<NSDictionary<NSString *,id> *> *)recentDiagnostics { return [SJDiagnostics snapshot]; }

+ (BOOL)reloadPreferencesFromUserDefaults:(NSUserDefaults *)defaults error:(NSError **)error {
    if(!defaults){ if(error)*error=SJCoreMakeError(SJCoreErrorInvalidArgument,@"User defaults must not be nil."); return NO; }
    SJConfiguration *config=[SJPreferences configurationFromUserDefaults:defaults];
    return [self applyConfiguration:config error:error];
}
+ (void)persistConfigurationToUserDefaults:(NSUserDefaults *)defaults { if(!defaults)return; [SJPreferences writeConfiguration:[self configuration] toUserDefaults:defaults]; }

+ (void)resetConfiguration {
    SJStateCoordinator *state=[SJStateCoordinator shared];
    // One atomic state transition: observers can only observe the final snapshot.
    NSDictionary *snapshot;
    @synchronized(state){
        state.configuration=[SJConfiguration defaultConfiguration];
        [state.products removeAllObjects];
        [state.productOrder removeAllObjects];
        [state.productDelegates removeAllObjects];
        [state.transactionObservers removeAllObjects];
        [state.seenTransactions removeAllObjects];
        [state.diagnostics removeAllObjects];
        snapshot=[[state.configuration dictionaryRepresentation] copy];
    }
    [SJDiagnostics appendModule:@"Core" message:@"Configuration and test session reset." code:0];
    SJPostStateChanged(snapshot);
}

@end
