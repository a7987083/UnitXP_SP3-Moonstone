#pragma once
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, ZNInputMode) {
    ZNInputModeSystemText = 0,
    ZNInputModeInteger = 1,
    ZNInputModeDecimal = 2,
    ZNInputModeHexAddress = 3,
    ZNInputModeHexBytes = 4,
    ZNInputModeNumericFlexible = 5,
};

FOUNDATION_EXPORT void ZNInputServiceBindField(UITextField *field, ZNInputMode mode)
    __attribute__((visibility("hidden")));

FOUNDATION_EXPORT void ZNInstallStandaloneNumericKeypadDeferred(void)
    __attribute__((visibility("hidden")));
