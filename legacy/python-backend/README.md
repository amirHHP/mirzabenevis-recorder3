# Python backend (legacy)

This was the original architecture using FastAPI + faster-whisper over WebSocket.

The app has been rewritten as a **native macOS menu bar app** using:
- Swift + SwiftUI (MenuBarExtra)
- ScreenCaptureKit (system audio)
- whisper.cpp (on-device, Metal/CoreML)

See the root README for the current setup.

## Running legacy backend (optional)

```bash
cd legacy/python-backend
python3.11 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python main.py
```
