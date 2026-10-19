# Examly

Examly contains a Flutter web client and an ASP.NET Core API for importing,
publishing, taking, and analyzing exams.

## Local backend configuration

Machine-specific database connection strings and JWT signing keys are not
stored in the public appsettings files. For local development, create an
`appsettings.Development.json` beside each backend appsettings file that needs
local settings. These files are ignored by Git.

For `backend/10.2.0/aspnet-core/src/TOEIC.Web.Host`, set at least:

```json
{
  "ConnectionStrings": {
    "Default": "<your SQL Server connection string>"
  },
  "Authentication": {
    "JwtBearer": {
      "SecurityKey": "<a private key of at least 32 bytes>"
    }
  }
}
```

Set the database connection string in the Migrator's local settings as well
before applying migrations. Keep signing keys and database credentials private;
use your deployment platform's secret store outside development.

## Run locally

Start the API from `backend/10.2.0/aspnet-core/src/TOEIC.Web.Host` with the
`TOEIC.Web.Host` launch profile, then start the Flutter web app from `frontend`:

```powershell
flutter run -d web-server --web-hostname 0.0.0.0 --web-port 7359
```

The Flutter API URL defaults to `https://localhost:44311` and can be overridden
with `--dart-define=EXAM_API_BASE_URL=<api-url>`.
