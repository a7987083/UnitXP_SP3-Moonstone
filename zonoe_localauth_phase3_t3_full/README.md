# ZonoeLocalAuth Phase3 T3 Full

Explicit auth adapter for the authorized test project.

## Client exports

- `ZonoeAuthLogin(username, password, completion)`
- `ZonoeAuthRegister(username, password, channel, completion)`
- `ZonoeAuthChangePassword(username, oldPassword, newPassword, completion)`

Endpoints:

- `POST /auth/login`
- `POST /auth/register`
- `POST /auth/change_password`

The adapter logs only operation names, status, message, and input lengths. It never writes raw passwords to the log.

## Server responses

Login: `AUTH_OK`, `PASSWORD_INVALID`, `ACCOUNT_NOT_FOUND`, `ACCOUNT_DISABLED`.

Register: `REGISTER_OK`, `ACCOUNT_EXISTS`.

Password change: `CHANGE_PASSWORD_OK`, `OLD_PASSWORD_INVALID`, `ACCOUNT_NOT_FOUND`, `ACCOUNT_DISABLED`, `NEW_PASSWORD_SAME_AS_OLD`.

## Deployment

Copy the three PHP files from `server/` to the server auth directory and fill DB credentials locally only. Do not commit database passwords.

Add rewrite rules if needed:

```
RewriteRule ^auth/login$ /auth/login.php [L]
RewriteRule ^auth/register$ /auth/register.php [L]
RewriteRule ^auth/change_password$ /auth/change_password.php [L]
```

The current compatibility database stores legacy passwords directly. For a later production migration, move newly managed accounts to password hashes without changing the client API contract.
