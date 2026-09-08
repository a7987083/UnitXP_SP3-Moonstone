# ZonoeLocalAuth Phase1 v0.1

Purpose: prove that the game can continue from its existing `kSmpcQPLoginNotification` boundary without invoking the third-party login UI on a subsequent run.

Behavior:
1. Swizzles `CustomAppController -smpcQpLoginResult:` to capture only `uid`, `user_name`, `user_token` from a successful game login callback into NSUserDefaults.
2. Swizzles `SMPCQuickSDK -login` and presents a test chooser.
3. First run: choose `原 SDK 登录`; after successful login the callback is cached.
4. Next run: choose `本地缓存登录（测试）`; the dylib posts `kSmpcQPLoginNotification` using the cached identity callback and does not call the original SDK login method.
5. Log: `Documents/ZonoeLocalAuth_Phase1_v0.1.log`.

Important: this is a Phase1 compatibility proof, not the final independent account system. The cached `user_token` still originated from the existing backend and may expire. Final replacement must issue a server-owned local account/session token and make local account identity authoritative.
