# Skills Analyzer — Flutter app

The college app for phones: students, parents, staff, HODs, placement officers and
admins all sign into the same build, and the menu adapts to what their roles allow.
It talks to the Go API in `../backend` and carries every module the web app has.

## Run it

Flutter lives at `C:\flutter`, so either add `C:\flutter\bin` to PATH once, or prefix
each command for this shell:

```bash
$env:PATH = "C:\flutter\bin;" + $env:PATH
```

Start the backend first (from `../backend`), then:

```bash
flutter pub get
flutter run
```

`flutter devices` lists what you can run on. Common targets:

| Target | Command |
| --- | --- |
| Android emulator / device | `flutter run -d emulator-5554` |
| Chrome (quickest to check a screen) | `flutter run -d chrome --web-port 5190` |
| Web server, no browser launch | `flutter run -d web-server --web-port 5190` |

## On a real phone

Turn on Developer options → USB debugging, plug the phone in and accept the prompt on
its screen. `flutter devices` should list it.

The phone's own `localhost` is the phone, not the laptop, so the API has to be reached
somehow. The simplest way — no laptop IP to look up, no firewall rule, works the same
on USB or Wi-Fi — is to let adb tunnel the port:

```bash
adb reverse tcp:8080 tcp:8080
flutter run --dart-define=API_URL=http://localhost:8080/api/v1
```

`adb reverse` has to be re-run whenever the device reconnects.

### Without the cable

With the phone still on USB, switch adb to Wi-Fi once:

```bash
adb tcpip 5555
adb connect <phone-ip>:5555
```

`adb shell ip route` prints the phone's address. Then unplug, re-run `adb reverse` and
`flutter run -d <phone-ip>:5555`. This works over a phone hotspot too, which is handy
when there is no shared Wi-Fi: the laptop joins the hotspot and the tunnel runs over it.

Reconnecting after a reboot needs the USB cable again, because `adb tcpip` does not
survive one. (Android 11+ can pair permanently through Developer options → Wireless
debugging if you would rather not plug in again.)

### Reaching the API directly instead

If you would rather not tunnel, point the app at the laptop's address on the shared
network — `ipconfig`, the Wi-Fi adapter's IPv4 — and allow the port through Windows
Firewall once, from an **Administrator** PowerShell:

```powershell
New-NetFirewallRule -DisplayName "Skills Analyzer API (dev)" -Direction Inbound -Protocol TCP -LocalPort 8080 -Action Allow -Profile Any
```

Then `flutter run --dart-define=API_URL=http://192.168.x.x:8080/api/v1`. Debug builds
allow plain HTTP to any address (`android/app/src/debug/res/xml/network_security_config.xml`);
release builds do not, so a deployed server needs HTTPS.

## Pointing it at an API

The default is picked for you: `http://10.0.2.2:8080/api/v1` on Android (that address
is the host machine as seen from the emulator) and `http://localhost:8080/api/v1`
everywhere else. Override it for a real phone or a deployed server:

```bash
flutter run --dart-define=API_URL=http://192.168.1.10:8080/api/v1
```

Two things to know when running against a laptop:

- The API's `CORS_ORIGINS` (in `backend/.env`) must list the web port you use.
  `http://localhost:5190` is already there.
- Plain HTTP is allowed only for `localhost`, `127.0.0.1` and `10.0.2.2`
  (`android/app/src/main/res/xml/network_security_config.xml` and the iOS
  `NSAllowsLocalNetworking` key). A deployed server should use HTTPS, which needs no
  change here.

## Two Android build settings worth knowing

Both are in the Gradle files with the same explanation, so nobody removes them by accident:

- **`kotlin.incremental=false`** (`android/gradle.properties`). The project is on `D:`
  while the pub cache holding the plugins' Kotlin sources is on `C:`. Kotlin's
  incremental compiler relativises those paths and that throws across Windows drive
  letters, so every plugin shipping Kotlin failed with "Could not close incremental
  caches". Putting the project and the pub cache on one drive would let this go.
- **`compileSdk = 36` forced on every subproject** (`android/build.gradle.kts`). Flutter
  pins plugin subprojects to compileSdk 34, but `flutter_plugin_android_lifecycle` —
  reached through `file_picker` and `image_picker` — demands 36. Setting it on `:app`
  alone does not reach the plugins. `minSdk` and `targetSdk` are untouched.

## Checks

```bash
flutter analyze   # no issues
flutter test      # access rules and formatting helpers
```

## Build

```bash
flutter build apk --release --dart-define=API_URL=https://api.yourcollege.edu/api/v1
flutter build appbundle --release --dart-define=API_URL=...   # for Play
flutter build ios --release --dart-define=API_URL=...         # needs a Mac
```

## How it is put together

```
lib/
  main.dart            app, session gate, SubPage/push helpers
  shell.dart           white app bar, dark drawer, feature → screen map
  theme.dart           the palette and widget themes
  auth/
    access.dart        which roles see which screens (mirrors web/src/auth/access.ts)
    session.dart       who is signed in, what they may do
  api/
    client.dart        Dio, token storage, silent refresh, error messages
    models.dart        the shapes the screens read
    endpoints.dart     every call, grouped by module
  widgets/             shared pieces: cards, meters, charts, pickers, file slots,
                       and the config-driven MasterCrud used by the lookup tables
  screens/             one file per module
```

Two rules worth keeping:

- **`auth/access.dart` decides visibility, not the screens.** A feature lists the
  permissions that reveal it and, where needed, the audiences it is limited to. The
  drawer, the dashboard tiles and the profile screen all read from that one list.
- **Screens call the API through `widgets/common.dart`'s helpers** (`runAction`,
  `toast`, `confirm`). They check `context.mounted` in one reviewed place, which is
  why `use_build_context_synchronously` is switched off in `analysis_options.yaml`.

## What each role gets

| Module | Admin / staff | Student | Parent |
| --- | --- | --- | --- |
| Dashboard | College figures and every module | Their own snapshot | Their children |
| Students | Roster, profiles, parents, documents | Own profile | Their children |
| Marks | Entry grid, result sheets | Own marks and CGPA | Children's marks |
| Skills | By class, skill master, subject → skill map, scoring weights | Own skills and scores | Children's skills |
| Careers | Student matches, catalogue, courses | Own matches, all careers | Their child's matches |
| Placement | Drives, offers, companies | Drives they can apply to | Placement status |
| Skill Analyzer | Rank and shortlist | Own skill gap | Child's skill gap |
| Classes, Staff, Users, Roles, Academic setup, Bulk upload, Documents, Reports, Year-end | Yes | — | — |
| Notifications | Inbox and announcements | Inbox | Inbox |

## Not here yet

Push notifications. The backend sends through Expo, which the React Native app at
`../mobile` uses; moving them to Firebase Cloud Messaging is the next step for this
app. Excel template downloads also open in a browser rather than saving in-app.
