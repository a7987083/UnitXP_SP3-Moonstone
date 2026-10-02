# ZonoPatch Cross-dylib API

M5.12 exposes a stable C ABI for use from another injected dylib.

## Required entry

`ZonoePatchActivate()` is the programmatic equivalent of the first ZN launcher tap. It does not bypass the deferred-bootstrap sequence; it enters the same Cold -> Loading -> Ready path and then lets the existing bootstrap call `ZonoePatchStart()` and `ZonoePatchShow()`.

The call is idempotent and may be issued off the main thread. It returns `false` only if the deferred bootstrap has already entered Failed state.

## Caller example

```c
#include <dlfcn.h>
#include <stdbool.h>

typedef bool (*ZonoePatchActivateFn)(void);

static bool StartZonoPatchFromPeerDylib(void) {
    ZonoePatchActivateFn activate =
        (ZonoePatchActivateFn)dlsym(RTLD_DEFAULT, "ZonoePatchActivate");
    return activate ? activate() : false;
}
```

If the target dylib was loaded with local symbol visibility, obtain its handle with `dlopen(..., RTLD_NOLOAD | RTLD_NOW)` and call `dlsym(handle, "ZonoePatchActivate")` instead.

Public declarations live in `src/ZonoePatchAPI.h`.
