import logging
from typing import Any

import numpy as np
from faster_whisper import WhisperModel

from config import (
    SAMPLE_RATE,
    WHISPER_COMPUTE_TYPE,
    WHISPER_DEVICE,
    WHISPER_MODEL,
)

logger = logging.getLogger(__name__)


class Transcriber:
    """Wraps faster-whisper for streaming word-level transcription."""

    def __init__(self, model_name: str | None = None) -> None:
        self._model: WhisperModel | None = None
        self._model_name = model_name or WHISPER_MODEL

    @property
    def model_name(self) -> str:
        return self._model_name

    def reload(self, model_name: str) -> None:
        """Unload current model and load a new one."""
        logger.info("Reloading Whisper model: %s -> %s", self._model_name, model_name)
        self._model = None
        self._model_name = model_name

    def _ensure_model(self) -> WhisperModel:
        if self._model is None:
            logger.info(
                "Loading Whisper model '%s' (device=%s, compute=%s)",
                self._model_name,
                WHISPER_DEVICE,
                WHISPER_COMPUTE_TYPE,
            )
            self._model = WhisperModel(
                self._model_name,
                device=WHISPER_DEVICE,
                compute_type=WHISPER_COMPUTE_TYPE,
            )
        return self._model

    def transcribe_chunk(
        self,
        pcm_bytes: bytes,
        language: str | None = None,
        time_offset: float = 0.0,
    ) -> dict[str, Any]:
        """Transcribe a PCM chunk and return word-level results."""
        if len(pcm_bytes) < SAMPLE_RATE * 2:  # less than 1 second
            return {"words": [], "text": "", "language": language}

        audio = np.frombuffer(pcm_bytes, dtype=np.int16).astype(np.float32) / 32768.0
        model = self._ensure_model()

        segments, info = model.transcribe(
            audio,
            language=language,
            word_timestamps=True,
            vad_filter=True,
            vad_parameters={"min_silence_duration_ms": 500},
        )

        words: list[dict[str, Any]] = []
        full_text_parts: list[str] = []

        for segment in segments:
            if segment.text.strip():
                full_text_parts.append(segment.text.strip())

            if segment.words:
                for word in segment.words:
                    if not word.word.strip():
                        continue
                    words.append(
                        {
                            "text": word.word.strip(),
                            "start": round(time_offset + (word.start or 0.0), 3),
                            "end": round(time_offset + (word.end or 0.0), 3),
                            "confidence": round(word.probability or 0.0, 3),
                        }
                    )

        detected_language = info.language if info else language

        return {
            "words": words,
            "text": " ".join(full_text_parts),
            "language": detected_language,
        }


transcriber = Transcriber()
