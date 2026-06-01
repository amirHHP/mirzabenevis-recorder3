import os

HOST = os.getenv("MIRZA_HOST", "127.0.0.1")
PORT = int(os.getenv("MIRZA_PORT", "8765"))

# faster-whisper model: tiny, base, small, medium, large-v3
WHISPER_MODEL = os.getenv("WHISPER_MODEL", "base")
WHISPER_DEVICE = os.getenv("WHISPER_DEVICE", "auto")  # auto, cpu, cuda
WHISPER_COMPUTE_TYPE = os.getenv("WHISPER_COMPUTE_TYPE", "int8")

# Audio format expected from client
SAMPLE_RATE = 16000
CHANNELS = 1
SAMPLE_WIDTH = 2  # 16-bit PCM

# Process audio in ~3 second chunks
CHUNK_DURATION_SEC = float(os.getenv("CHUNK_DURATION_SEC", "3.0"))

AVAILABLE_MODELS = ["tiny", "base", "small", "medium", "large-v3"]

MODEL_INFO = {
    "tiny": {"ram": "~1 GB", "speed": "fastest", "quality": "low"},
    "base": {"ram": "~1 GB", "speed": "fast", "quality": "medium"},
    "small": {"ram": "~2 GB", "speed": "moderate", "quality": "good"},
    "medium": {"ram": "~5 GB", "speed": "slow", "quality": "high"},
    "large-v3": {"ram": "~10 GB", "speed": "slowest", "quality": "best"},
}
