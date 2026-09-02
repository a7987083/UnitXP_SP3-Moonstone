#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *HFAPatchSupportDirectory(void);
FOUNDATION_EXPORT NSString *HFAPatchExternalConfigPath(void);
FOUNDATION_EXPORT NSString *HFAPatchLogPath(void);
FOUNDATION_EXPORT void HFAPatchLog(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);

NS_ASSUME_NONNULL_END
