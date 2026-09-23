#pragma once

#import <Foundation/Foundation.h>

// Single display-version source for the runtime menu UI.
// Update these values once per milestone; footer/status surfaces consume the
// composed display string instead of keeping historical version literals.
#define ZN_PRODUCT_VERSION @"0.5.8"
#define ZN_MILESTONE_VERSION @"M4.8"
#define ZN_MENU_VERSION_DISPLAY @"0.5.8 · M4.8"
#define ZN_MENU_VERSION_FEATURE @"Receiver + Multi-Arg + Return Capture"
