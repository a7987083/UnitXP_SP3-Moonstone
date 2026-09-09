# ZonoeLocalAuth Phase4 DualMode

Authorized test build for switching the existing SDK account backend between two modes without changing the SDK UI.

- 原 SDK 登录：calls the original `KCNetworkManager` implementation unchanged.
- 本地登录：redirects selected SDK account routes to the local test auth backend.
- A small floating button shows the active mode and reopens the chooser.
- The chooser is also shown shortly after launch.
- Request bodies and credential values are never written to the bridge log.
- Local `NSURLConnection` objects are retained during the request window to avoid premature ARC release.

Local mappings:

- `/Api/Common/Login` -> `/auth/login?compat=pandora`
- `/Api/Common/Register` -> `/auth/register?compat=pandora`
- known password/reset route names -> `/auth/change_password?compat=pandora`

Log file:

`Documents/ZonoeLocalAuth_Phase4_DualMode.log`
