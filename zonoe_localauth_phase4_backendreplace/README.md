# ZonoeLocalAuth Phase4 BackendReplace

Purpose: keep the existing Pandora SDK UI and interaction flow, while redirecting selected broken SDK backend routes to the project's own test Auth service.

Known static path mappings from the supplied iOSPandoraSDK binary:

- `/Api/Common/Login` -> `/auth/login?compat=pandora`
- `/Api/Common/Register` -> `/auth/register?compat=pandora`

The supplied binary exposes `http://sdkapi.%@.com/cysdkfloat/forgetpwd.php` for password recovery rather than a confirmed `/Api/Common/...` change-password path. Phase4 therefore includes a narrow route-name fallback (`forgetpwd`, `changepassword`, `change_password`, `resetpassword`, `reset_password`) -> `/auth/change_password?compat=pandora`. Runtime logs record only route names and body byte length; request bodies and credentials are never logged or parsed by the dylib.

The bridge replaces `-[KCNetworkManager KCNetworkHandleWithDomain:andBodyStr:andLoad:]` only when one of the selected account routes is matched. Non-account routes call the original implementation unchanged. For redirected requests the existing `KCNetworkManager` object remains the `NSURLConnection` delegate so the SDK's existing response parsing and UI callbacks can continue to run.

Server PHP files accept both the Phase3 field names and Pandora-compatible aliases such as `uname`. In `?compat=pandora` mode responses contain both the local `{ok,message,...}` shape and Pandora-style `{result,msg,data}` fields.

Important test limitation: this build replaces the Pandora account-backend request boundary. The later QuickSDK `/v2/users/checklogin` verification stage is a separate downstream boundary and is not changed in this Phase4 build. First validation target is to prove that tapping the original SDK Login/Register UI creates POST requests to `/auth/login` or `/auth/register` while the UI remains unchanged.

Server deployment: copy the three PHP files into `/home/ubuntu/runtime/www/auth/` and fill the same local DB credentials already verified in Phase3. Keep the existing RewriteRules for `auth/login`, `auth/register`, and `auth/change_password`.

Runtime log: `Documents/ZonoeLocalAuth_Phase4_BackendReplace.log`.
