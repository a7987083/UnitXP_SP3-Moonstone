#import "ZonoePatchAPI.h"
#import "ZNDeferredBootstrap.h"

extern "C" __attribute__((visibility("default"))) bool ZonoePatchActivate(void) {
    return ZNDeferredBootstrapActivate() ? true : false;
}
