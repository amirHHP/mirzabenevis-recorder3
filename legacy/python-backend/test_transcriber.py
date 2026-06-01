"""Tests for the transcription backend."""

import struct

import numpy as np
import pytest

from config import SAMPLE_RATE, SAMPLE_WIDTH
from transcriber import Transcriber


def _make_sine_pcm(duration_sec: float = 1.0, freq: float = 440.0) -> bytes:
    """Generate a sine wave PCM buffer (simulates audio input)."""
    n_samples = int(SAMPLE_RATE * duration_sec)
    t = np.linspace(0, duration_sec, n_samples, endpoint=False)
    samples = (np.sin(2 * np.pi * freq * t) * 16000).astype(np.int16)
    return samples.tobytes()


class TestTranscriber:
    def test_short_audio_returns_empty(self):
        transcriber = Transcriber()
        short = b"\x00\x00" * 100  # very short
        result = transcriber.transcribe_chunk(short)
        assert result["words"] == []
        assert result["text"] == ""

    def test_transcribe_chunk_structure(self):
        transcriber = Transcriber()
        pcm = _make_sine_pcm(duration_sec=2.0)
        result = transcriber.transcribe_chunk(pcm, language="en", time_offset=5.0)

        assert "words" in result
        assert "text" in result
        assert "language" in result
        assert isinstance(result["words"], list)

        for word in result["words"]:
            assert "text" in word
            assert "start" in word
            assert "end" in word
            assert word["start"] >= 5.0


class TestConfig:
    def test_sample_rate(self):
        assert SAMPLE_RATE == 16000

    def test_sample_width(self):
        assert SAMPLE_WIDTH == 2

    def test_chunk_bytes_calculation(self):
        from config import CHUNK_DURATION_SEC

        chunk_bytes = int(SAMPLE_RATE * SAMPLE_WIDTH * CHUNK_DURATION_SEC)
        assert chunk_bytes == 96000  # 3 sec * 16000 * 2

    def test_available_models(self):
        from config import AVAILABLE_MODELS

        assert "base" in AVAILABLE_MODELS
        assert "large-v3" in AVAILABLE_MODELS


class TestTranscriberReload:
    def test_reload_changes_model_name(self):
        t = Transcriber(model_name="base")
        assert t.model_name == "base"
        t.reload("small")
        assert t.model_name == "small"
