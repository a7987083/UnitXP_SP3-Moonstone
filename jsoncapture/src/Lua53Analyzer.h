#import <Foundation/Foundation.h>

FOUNDATION_EXPORT NSInteger JC4FindLua53SignatureOffset(NSData *data);
FOUNDATION_EXPORT void JC4AnalyzeLua53Data(NSData *data,
                                            NSString *source,
                                            NSString *chunkName,
                                            NSString *rootPath);
