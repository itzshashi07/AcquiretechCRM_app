# Acquiretech CRM — Android app

The native Android app for the Acquiretech CRM workspace
(`https://crm.acquiretechsoftwaresolution.in`). It works with the same backend as the
web workspace ([CRM_Self_hosted](https://github.com/itzshashi07/CRM_Self_hosted)) and
uses the same accounts, roles and data.

## What it does

- **Instant enquiry alerts.** When someone fills a form on the website, the phone gets a
  notification within about a second (Firebase Cloud Messaging), even when the app is
  closed. Tapping it opens that lead. Follow-up reminders and assignments arrive the same way.
- **Leads, deals, contacts, companies and tasks.** Search, stage filters, infinite scroll,
  create and edit, stage changes, lead conversion, and a pipeline summary.
- **Lead pages built for acting fast.** One tap to call, WhatsApp or email. The full website
  brief (budget, timeline, preferred contact). A timeline of calls, notes and follow-ups,
  plus quick logging and follow-up scheduling.
- **Follow-ups agenda.** Today, overdue, upcoming and done, with one-tap completion.
- **Team & roles (admins).** Add members, choose their role and team, reset passwords and
  remove access. Managers can view their team. Each role's permissions are explained in the
  app and enforced by the server.
- **Role-aware UI.** Employees see only their tasks. Only admins see team management and delete.
- **Fast.** The last session, dashboard and lists are cached on the device, so the app opens
  and paints instantly, then refreshes. Fonts are bundled.

## Roles

| Role        | Can do                                                                                     |
| ----------- | ------------------------------------------------------------------------------------------ |
| Admin       | Every record; team members, roles and access; workflow and automations; delete records     |
| Manager     | Records owned by their team; team-shared lead assignment; view team                         |
| Salesperson | Only their own leads, contacts, companies, deals and tasks                                  |
| Employee    | Only their own tasks                                                                        |

## Project layout

```
lib/
  core/      config, API client (session cookie + Origin), models, app state, push (FCM)
  ui/        brand theme (website palette, Inter + Fraunces), logo, shared widgets
  features/  login, shell, home, records, record detail/form, follow-ups,
             notifications, team, more
assets/      AQ logo, launcher icon sources, bundled fonts
```

## Build and install

Requirements: Flutter 3.44+, Android SDK 37, JDK 17+.

Two files are kept out of Git and must be present locally:

1. `android/app/google-services.json` — Firebase config for app
   `in.acquiretech.acquiretech_crm` in project `heyshashi-259f5`:
   ```sh
   firebase apps:sdkconfig ANDROID 1:842602890965:android:4cc01772e29a43e922445c \
     -P heyshashi-259f5 -o android/app/google-services.json
   ```
2. `android/key.properties` and `android/keystore/acquiretech-crm-release.jks` — the release
   signing key. **Keep a backup.** Updates must be signed with the same key, otherwise the app
   has to be uninstalled first.

```sh
flutter pub get
flutter test
flutter build apk --release --target-platform android-arm64
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

For testing against a local backend over USB:

```sh
adb reverse tcp:43872 tcp:43872
flutter build apk --release --dart-define=CRM_ORIGIN=http://localhost:43872
```

Plain HTTP is accepted only for `localhost`; everything else must be HTTPS.

## Notifications

The backend sends through FCM HTTP v1. It needs `FCM_SERVICE_ACCOUNT` (base64 of the Firebase
service-account JSON for project `heyshashi-259f5`) in its `.env.production`. The app registers
its token at `POST /api/push/app` after sign-in, and signing out removes it. Removing a
member's access also removes their devices. Messages use the `crm_alerts` channel with the
Acquiretech AQ icon.
