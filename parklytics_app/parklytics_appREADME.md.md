# 📱 Parklytics — Flutter Mobile App

The mobile frontend for the Parklytics street parking intelligence system. Built with Flutter, it displays a real-time parking heatmap, recommends the best available road, and navigates the user to their parking spot.

---

## ✨ Features

- **Live parking heatmap** — color-coded road overlays (🟢 Available / 🟠 Medium / 🔴 Busy)
- **Smart parking recommendation** — suggests the best road based on live occupancy data from the Flask backend
- **Turn-by-turn navigation** — routes user from current location to recommended parking spot via OSRM API
- **Location search** — Nominatim-powered address search with typeahead suggestions
- **Demo mode** — simulates a full drive to the beach for testing without physical movement
- **Crowdsourced events** — sends parking detected / Bluetooth disconnect events back to the backend
- **User feedback** — lets users report whether they found parking easily, improving future predictions

---

## 🛠️ Tech Stack

| Feature | Technology |
|---|---|
| Framework | Flutter (Dart) |
| Maps | flutter_map + OpenStreetMap tiles |
| Routing | OSRM API (open-source routing) |
| Location Search | Nominatim geocoding API |
| GPS | geolocator |
| Animations | flutter_map_animations |
| Backend | Flask REST API (see `/` root of repo) |

---

## ⚙️ Setup

### Prerequisites
- Flutter SDK installed (`flutter --version`)
- Android Studio or VS Code with Flutter extension
- Android emulator or physical device

### Run the app

```bash
cd parklytics_app
flutter pub get
flutter run
```

### Connect to backend
Make sure the Flask backend is running:
```bash
# From the repo root
python server.py
```
Then update the base URL in `lib/main.dart` to your machine's local IP:
```dart
// Replace with your machine's IP address
static const String _baseUrl = 'http://192.168.x.x:5000';
```

---

## 📁 Structure

```
parklytics_app/
├── lib/
│   └── main.dart          # Full app — map, navigation, UI, API calls
├── assets/
│   └── car.png            # Car icon for map marker
├── pubspec.yaml           # Dependencies
└── analysis_options.yaml  # Lint rules
```

---

## 🗺️ App Flow

```
Launch → GPS Permission → Load Map → Fetch Road Geometries (OSRM)
           ↓
     Search Destination → Recommend Parking Road → Show Route
           ↓
     Start Navigation → Demo Drive → Arrive → Submit Feedback
```
