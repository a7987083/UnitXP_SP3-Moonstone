#pragma once
#include <stdbool.h>

/*
 Host dylib bridge contract.

 Preferred passive integration:
   export ZonoeHostGetUDID() and ZonoeHostIsAuthorized() from the main dylib.
 ZonoePatch resolves them with dlsym(RTLD_DEFAULT, ...) and never changes the
 main dylib's authorization result.

 Alternative push integration:
   after the main dylib has completed its own authorization, call
   ZonoePatchSubmitHostIdentity(udid, true).
*/

#ifdef __cplusplus
extern "C" {
#endif

__attribute__((visibility("default"))) const char *ZonoeHostGetUDID(void);
__attribute__((visibility("default"))) bool ZonoeHostIsAuthorized(void);

__attribute__((visibility("default"))) void ZonoePatchSubmitHostIdentity(const char *udid, bool authorized);

#ifdef __cplusplus
}
#endif
