#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef BOOL (^ODLRShouldYieldBlock)(void);
typedef void (^ODLRProgressBlock)(NSDictionary *event);

/// Scan raw_textasset and (re)generate Lua 5.3 files in decoded_lua.
/// It never executes Lua bytecode. ENCM payloads are decoded with the observed
/// 4-byte header + XOR 0x4D scheme. Returns cumulative/batch statistics.
FOUNDATION_EXPORT NSDictionary *ODLRDecryptRawDirectory(NSString *rawDirectory,
                                                         NSString *decodedDirectory,
                                                         NSString *stateRoot,
                                                         BOOL forceAll,
                                                         ODLRShouldYieldBlock _Nullable shouldYield,
                                                         ODLRProgressBlock _Nullable progress);

/// Statically interprets data-construction opcodes from decoded Lua 5.3 chunks
/// and writes recovered JSON. Dynamic opcodes stop the current group; already
/// reconstructed tables are retained as partial output.
FOUNDATION_EXPORT NSDictionary *ODLRRecoverDecodedDirectory(NSString *decodedDirectory,
                                                             NSString *outputRoot,
                                                             BOOL forceAll,
                                                             ODLRShouldYieldBlock _Nullable shouldYield,
                                                             ODLRProgressBlock _Nullable progress);

/// Fast inventory used by the g4 UI. Counts are estimates based on persisted
/// indices and current directory contents; no Lua execution occurs.
FOUNDATION_EXPORT NSDictionary *ODLRQueueSnapshot(NSString *rawDirectory,
                                                   NSString *decodedDirectory,
                                                   NSString *outputRoot);

/// Remove only recovery/decrypt bookkeeping so existing captured files remain.
FOUNDATION_EXPORT void ODLRResetRecoveryIndex(NSString *outputRoot);
FOUNDATION_EXPORT void ODLRResetDecryptIndex(NSString *stateRoot);

NS_ASSUME_NONNULL_END
