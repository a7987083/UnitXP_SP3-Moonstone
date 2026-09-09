# ZonoeLocalAuth Phase2 T3R

Explicit login/register Auth Adapter for the authorized test project.

## Client exports

- `ZonoeAuthLogin(username, password, completion)` -> `/auth/login`
- `ZonoeAuthRegister(username, password, channel, completion)` -> `/auth/register`

No Pandora/QuickSDK network interception is installed. The test project calls the adapter explicitly.

## Registration behavior

Server endpoint writes `db_adv_login.t_tb_account` and returns:

- `REGISTER_OK`
- `ACCOUNT_EXISTS`
- `ACCOUNT_OR_PASSWORD_EMPTY`
- `ACCOUNT_OR_PASSWORD_INVALID`
- DB/lock errors

Observed account ids are contiguous from 1048577 to 1048605. Because `id` is not AUTO_INCREMENT, `register.php` serializes allocation with a MySQL named lock and uses `MAX(id)+1`.

`channel` is optional and is stored as NULL when omitted; the adapter does not guess project channel semantics.

## Server deployment

Copy `server/register.php` to:

`/home/ubuntu/runtime/www/auth/register.php`

Fill the same MySQL connection values used by the working `/auth/login` endpoint. Do not commit real DB credentials.
