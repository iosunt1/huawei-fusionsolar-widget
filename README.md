# Huawei FusionSolar Widget

> This project was created with the assistance of AI.

Widgets for a Huawei FusionSolar plant: a native macOS WidgetKit widget and a KDE Plasma 6 widget. They show current PV power, battery charge, home load, grid flow and today's production.

## macOS widget

The native widget and its account setup app are in `macOS/`. They require macOS 14 or newer and Xcode 15 or newer.

1. Open `macOS/FusionSolarWidget.xcodeproj` in Xcode.
2. Select a development team for both the **FusionSolarWidget** app and **FusionSolarWidgetExtension** targets. The shared App Group identifier is `group.com.goitonthefloor.fusionsolarwidget`; register it for the selected team if needed.
3. Build and run the **FusionSolarWidget** app, enter the FusionSolar host, username and password, then choose **Save and refresh**.
4. Add **Huawei FusionSolar** from the macOS widget gallery in Notification Center or on the desktop.

The widget provides small and medium layouts with live PV power, battery state of charge, home consumption, grid flow and today's yield. macOS controls the widget refresh schedule; the extension requests a new timeline about every 15 minutes. The app and widget share account settings through their sandboxed App Group container, including the password.

The shared FusionSolar client can be built with Swift Package Manager:

```bash
swift build --package-path macOS/FusionSolarKit
```

The existing Plasma widget remains available below.

## What it shows

- PV power right now, in kW
- Battery state of charge, plus whether it is charging or discharging
- Home consumption and grid import or export
- Today's PV yield, in kWh
- The plant name, when the account has one

The panel icon shows power and battery charge. Click it to open the full view. On the desktop the full view is shown directly.

## Install

Plasma 6 and `python3` are required. `python3` performs the HTTP requests, because the QML request object cannot read the FusionSolar session cookie. Plasma runs that helper through its executable data engine (`plasma5support`).

```bash
git clone https://github.com/GoitontheFloor/huawei-fusionsolar-widget.git
cd huawei-fusionsolar-widget
kpackagetool6 -t Plasma/Applet --install .
```

Upgrade an existing copy with:

```bash
kpackagetool6 -t Plasma/Applet --upgrade .
```

Then add **Huawei FusionSolar** from Add Widgets. Right-click it and choose **Configure**.

If a previous broken copy is still on the panel, remove that widget and add it again after upgrading.

## Configure

- **Host**: the FusionSolar website host, for example `eu5.fusionsolar.huawei.com`. A regional host such as `uni003eu5.fusionsolar.huawei.com` is accepted and normalized.
- **Username** and **Password**: the same login as the FusionSolar website.
- **Plant DN**: optional. Leave it empty to use the first plant on the account.
- **Refresh**: how often live data is requested. The default is 30 seconds. The login session is kept and is not repeated on every refresh.

The password is stored only in the local Plasma configuration. FusionSolar sometimes asks for a captcha. When that happens, sign in once in the browser and refresh the widget.

## Layout

```
metadata.json
contents/ui/main.qml
contents/ui/FullRepresentation.qml
contents/ui/CompactRepresentation.qml
contents/ui/StatTile.qml
contents/ui/ConfigGeneral.qml
contents/config/main.xml
contents/config/config.qml
contents/code/api.js
contents/code/fshttp.py
contents/code/jsrsasign.js
```

`api.js` follows the FusionSolar website login used by the Home Assistant FusionSolar App integration: public key, RSA-OAEP with SHA-384, session cookie, CSRF token, then the energy-flow and energy-balance requests.

## Tests

```bash
node tests/api_test.js
python3 tests/http_test.py
swift test --package-path macOS/FusionSolarKit
```

## License

GPL-3.0-or-later. `jsrsasign.js` keeps its own license header.

## Deutsch

Ein Plasma-6-Widget für eine Huawei-FusionSolar-Anlage. Es zeigt aktuelle PV-Leistung, Batterieladestand, Hausverbrauch, Netzfluss und den Ertrag von heute.

### Installation

Plasma 6 und `python3` werden benötigt.

```bash
git clone https://github.com/GoitontheFloor/huawei-fusionsolar-widget.git
cd huawei-fusionsolar-widget
kpackagetool6 -t Plasma/Applet --install .
```

Danach das Widget **Huawei FusionSolar** hinzufügen und über Rechtsklick konfigurieren. Host, Benutzername und Passwort sind dieselben wie auf der FusionSolar-Webseite. Die Anlagen-DN kann leer bleiben. Das Passwort bleibt in der lokalen Plasma-Konfiguration.

Wenn FusionSolar ein Captcha verlangt, einmal im Browser anmelden und das Widget aktualisieren.
