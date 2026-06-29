# Green-Life-Assistant

An iOS eco-living assistant for Hong Kong residents to track carbon footprints, classify waste, and locate recycling points.

## Features

- **Dashboard** — Full-screen video background showing today's carbon footprint & AQHI
- **Map** — Hong Kong recycling station map (GeoJSON) with walking directions
- **AR Scanner** — Real-time garbage detection & classification (CoreML + Vision)
- **News** — RSS feed aggregator (EPD, Earth911, Columbia Climate)
- **AI Chat** — OpenAI-compatible eco-assistant with image recognition
- **Carbon Footprint Input** — 16 activity emission factors, stored in Supabase

## Tech Stack

- **SwiftUI** + Observation (iOS 17+)
- **ARKit** + **RealityKit** — AR anchor tracking & 3D labels
- **Vision** + **CoreML** — Custom garbage detection model
- **Supabase** — Backend (auth, database)
- **OpenAI-compatible API** — AI chat (opencode.ai)

## Getting Started

```bash
cp Green-Life-Assistant/Secrets.plist.sample Green-Life-Assistant/Secrets.plist
# Edit Secrets.plist with your Supabase and OpenAI keys
```

Open `Green-Life-Assistant.xcodeproj` in Xcode and press `Cmd+R`.

## Project Structure

```
Green-Life-Assistant/
├── Green-Life-Assistant/
│   ├── Model/          # Data models (User, CFRecord, Emission, AQHI...)
│   ├── Tools/          # Utilities (Supabase, Auth, Config, Location...)
│   ├── Views/          # Views (Dashboard, Map, AR, Chat, Profile...)
│   ├── Resources/      # Resources (ML models, videos, fonts, GeoJSON)
│   └── Assets.xcassets
├── Green-Life-Assistant.xcodeproj
└── Secrets.plist.sample
```
