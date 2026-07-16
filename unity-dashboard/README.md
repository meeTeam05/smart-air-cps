# Smart Air Unity Dashboard

Unity desktop visualization for the Smart Air CPS. The application authenticates with the Fastify backend, polls a device shadow endpoint, and displays sensor and relay data in a dashboard with real-time charts.

## Data flow

1. `AuthManager` signs in through `POST /api/auth/login` and keeps the access and refresh tokens in memory.
2. `ApiManager` polls `GET /api/devices/{deviceId}/shadow` every two seconds with a bearer token.
3. The response is deserialized into the reported device state.
4. `DashboardManager` updates temperature, humidity, CO, NO2, relay states, device mode, and the four chart feeds.

## Requirements

- Unity `6000.3.12f1`
- The packages declared in `Packages/manifest.json`
- [EasyChart Lite](https://assetstore.unity.com/packages/slug/359794) from the Unity Asset Store
- Access to the Smart Air backend configured in `Assets/Scripts/Utils/Constants.cs`

EasyChart source files are intentionally not committed because they are distributed through the Unity Asset Store. Import EasyChart Lite before opening the dashboard scene. The four project-specific chart profiles are stored in `Assets/SmartAirChartProfiles/`.

## Setup

1. Open `unity-dashboard/` in Unity Hub using Unity `6000.3.12f1`.
2. Import EasyChart Lite from the Unity Asset Store.
3. Open `Assets/Scenes/Game.unity`.
4. Select the GameObject containing `ApiManager`.
5. Configure `Email`, `Password`, and `Device Id` in the Inspector.
6. Run `Assets/Scenes/MainMenu.unity` or add both configured scenes to a desktop build.

No account password or API token is committed to the repository. Do not save real credentials into a scene that will be pushed to Git.

## Project structure

- `Assets/Scripts/API/`: login, token refresh, and device shadow polling
- `Assets/Scripts/Models/`: backend response models
- `Assets/Scripts/Dashboard/`: UI state updates
- `Assets/Scripts/Chart/`: rolling sensor-chart logic and axis strategies
- `Assets/SmartAirChartProfiles/`: project-specific EasyChart profiles
- `Assets/Scenes/`: main menu and dashboard scenes
