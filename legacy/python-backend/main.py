"""
Mirza Benevis — Local transcription server.

Receives 16 kHz mono PCM audio over WebSocket, transcribes with faster-whisper,
and streams word-level results back to the Mac client.
"""

import asyncio
import json
import logging
from typing import Any

import uvicorn
from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from config import (
    AVAILABLE_MODELS,
    CHUNK_DURATION_SEC,
    HOST,
    MODEL_INFO,
    PORT,
    SAMPLE_RATE,
    SAMPLE_WIDTH,
    WHISPER_COMPUTE_TYPE,
    WHISPER_DEVICE,
)
from transcriber import transcriber

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger(__name__)

CHUNK_BYTES = int(SAMPLE_RATE * SAMPLE_WIDTH * CHUNK_DURATION_SEC)

app = FastAPI(title="Mirza Benevis Transcription Server", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
async def health() -> dict[str, str]:
    return {
        "status": "ok",
        "service": "mirza-benevis-transcriber",
        "whisper_model": transcriber.model_name,
    }


class ConfigUpdate(BaseModel):
    whisper_model: str | None = None


@app.get("/api/config")
async def get_config() -> dict[str, Any]:
    return {
        "whisper_model": transcriber.model_name,
        "device": WHISPER_DEVICE,
        "compute_type": WHISPER_COMPUTE_TYPE,
        "available_models": AVAILABLE_MODELS,
        "model_info": MODEL_INFO,
    }


@app.post("/api/config")
async def update_config(body: ConfigUpdate) -> dict[str, Any]:
    if body.whisper_model is not None:
        if body.whisper_model not in AVAILABLE_MODELS:
            raise HTTPException(
                status_code=400,
                detail=f"Invalid model. Choose from: {AVAILABLE_MODELS}",
            )
        transcriber.reload(body.whisper_model)
    return {
        "whisper_model": transcriber.model_name,
        "message": "Config updated. Model will load on next transcription.",
    }


@app.get("/api/models")
async def list_models() -> dict[str, Any]:
    return {
        "current": transcriber.model_name,
        "models": AVAILABLE_MODELS,
        "info": MODEL_INFO,
    }


@app.websocket("/ws/transcribe")
async def websocket_transcribe(websocket: WebSocket) -> None:
    await websocket.accept()
    logger.info("WebSocket client connected")

    audio_buffer = bytearray()
    time_offset = 0.0
    language: str | None = None

    try:
        while True:
            message = await websocket.receive()

            if message.get("type") == "websocket.disconnect":
                break

            # Control messages (JSON text)
            if "text" in message and message["text"]:
                try:
                    control = json.loads(message["text"])
                    msg_type = control.get("type")

                    if msg_type == "config":
                        language = control.get("language")
                        await websocket.send_json(
                            {
                                "type": "config_ack",
                                "language": language,
                                "chunk_duration": CHUNK_DURATION_SEC,
                            }
                        )
                        logger.info("Config received: language=%s", language)

                    elif msg_type == "flush":
                        if audio_buffer:
                            result = await _transcribe_buffer(
                                bytes(audio_buffer), language, time_offset
                            )
                            await websocket.send_json(result)
                            duration = len(audio_buffer) / (SAMPLE_RATE * SAMPLE_WIDTH)
                            time_offset += duration
                            audio_buffer.clear()

                    elif msg_type == "ping":
                        await websocket.send_json({"type": "pong"})

                except json.JSONDecodeError:
                    await websocket.send_json(
                        {"type": "error", "message": "Invalid JSON control message"}
                    )
                continue

            # Binary audio data
            if "bytes" in message and message["bytes"]:
                audio_buffer.extend(message["bytes"])

                while len(audio_buffer) >= CHUNK_BYTES:
                    chunk = bytes(audio_buffer[:CHUNK_BYTES])
                    del audio_buffer[:CHUNK_BYTES]

                    result = await _transcribe_buffer(chunk, language, time_offset)
                    await websocket.send_json(result)
                    time_offset += CHUNK_DURATION_SEC

    except WebSocketDisconnect:
        logger.info("WebSocket client disconnected")
    except Exception as exc:
        logger.exception("WebSocket error: %s", exc)
        try:
            await websocket.send_json({"type": "error", "message": str(exc)})
        except Exception:
            pass


async def _transcribe_buffer(
    pcm_bytes: bytes,
    language: str | None,
    time_offset: float,
) -> dict[str, Any]:
    loop = asyncio.get_event_loop()
    result = await loop.run_in_executor(
        None,
        transcriber.transcribe_chunk,
        pcm_bytes,
        language,
        time_offset,
    )
    return {"type": "transcription", **result}


def main() -> None:
    logger.info("Starting Mirza Benevis server on %s:%d", HOST, PORT)
    uvicorn.run(
        "main:app",
        host=HOST,
        port=PORT,
        reload=False,
        log_level="info",
    )


if __name__ == "__main__":
    main()
