#!/usr/bin/env python3
"""Persistent MLX Whisper worker for Foxtation.

The model is loaded once and reused for every utterance. That is what makes
interactive dictation possible: spawning `mlx_whisper` per recording costs
several seconds of interpreter start-up and weight loading every time, whereas
a resident worker answers in a fraction of a second.

Protocol: one JSON object per line on stdin, one JSON object per line on
stdout. Anything the libraries print goes to stderr so the channel stays clean.
"""

import json
import os
import sys
import time
import traceback

os.environ.setdefault("HF_HUB_DISABLE_PROGRESS_BARS", "1")
os.environ.setdefault("TRANSFORMERS_VERBOSITY", "error")
os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")

# Chatty imports must not write to stdout, which carries the protocol.
_real_stdout = os.dup(1)
os.dup2(2, 1)

import numpy as np  # noqa: E402
import mlx.core as mx  # noqa: E402
from mlx_whisper.audio import N_FRAMES, load_audio, log_mel_spectrogram, pad_or_trim  # noqa: E402
from mlx_whisper.decoding import DecodingOptions, DecodingResult, decode  # noqa: E402
from mlx_whisper.load_models import load_model  # noqa: E402
from mlx_whisper.tokenizer import LANGUAGES, get_tokenizer  # noqa: E402

os.dup2(_real_stdout, 1)
os.close(_real_stdout)

_out = os.fdopen(1, "w", buffering=1)
# Any later print() from libraries goes to stderr, never the protocol channel.
sys.stdout = sys.stderr


def emit(payload):
    _out.write(json.dumps(payload, ensure_ascii=False) + "\n")
    _out.flush()


def compression_ratio(text):
    """Whisper's guard against repetition loops."""
    raw = text.encode("utf-8")
    if not raw:
        return 0.0
    import zlib
    return len(raw) / max(1, len(zlib.compress(raw)))


def main():
    repo = sys.argv[1] if len(sys.argv) > 1 else "mlx-community/whisper-large-v3-turbo"

    try:
        started = time.time()
        model = load_model(repo, dtype=mx.float16)
        mx.eval(model.parameters())
        # Compile the Metal kernels now instead of on the first real dictation.
        mlx_whisper_silence = np.zeros(16000, dtype=np.float32)
        warm = pad_or_trim(
            log_mel_spectrogram(mlx_whisper_silence, n_mels=model.dims.n_mels),
            N_FRAMES, axis=-2,
        ).astype(mx.float16)
        decode(model, warm, DecodingOptions(language="en", task="transcribe",
                                            temperature=0.0, fp16=True,
                                            without_timestamps=True))
        emit({"ready": True, "model": repo, "load_seconds": round(time.time() - started, 2)})
    except Exception as exc:  # noqa: BLE001
        emit({"ready": False, "error": f"{type(exc).__name__}: {exc}"})
        traceback.print_exc(file=sys.stderr)
        return 1

    tokenizers = {}

    def tokenizer_for(language, task):
        key = (language, task)
        if key not in tokenizers:
            tokenizers[key] = get_tokenizer(
                model.is_multilingual, num_languages=model.num_languages,
                language=language, task=task,
            )
        return tokenizers[key]

    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        if line == "quit":
            break
        try:
            request = json.loads(line)
        except json.JSONDecodeError as exc:
            emit({"ok": False, "error": f"bad request: {exc}"})
            continue

        audio = request.get("audio")
        if not audio or not os.path.exists(audio):
            emit({"ok": False, "error": f"audio not found: {audio}"})
            continue

        started = time.time()
        try:
            task = request.get("task", "transcribe")
            samples = load_audio(audio)
            mel = log_mel_spectrogram(samples, n_mels=model.dims.n_mels)
            content_frames = mel.shape[0]

            language = request.get("language") or None
            if language in (None, "auto"):
                probe = pad_or_trim(mel, N_FRAMES, axis=-2).astype(mx.float16)
                _, probs = model.detect_language(probe)
                language = max(probs, key=probs.get)
                detected = language
            else:
                detected = language

            tokenizer = tokenizer_for(language, task)
            prompt = request.get("prompt") or None
            pieces = []
            seek = 0
            while seek < content_frames:
                size = min(N_FRAMES, content_frames - seek)
                segment = pad_or_trim(mel[seek:seek + size], N_FRAMES, axis=-2).astype(mx.float16)

                result = None
                for temperature in (0.0, 0.2, 0.4, 0.6, 0.8, 1.0):
                    options = DecodingOptions(
                        task=task, language=language, temperature=temperature,
                        fp16=True, without_timestamps=True, prompt=prompt,
                    )
                    candidate = decode(model, segment, options)
                    result = candidate
                    text = decode_text(tokenizer, candidate)
                    if compression_ratio(text) < 2.4 or temperature == 1.0:
                        break

                if result is None:
                    seek += size
                    continue
                if result.no_speech_prob < 0.6 or result.avg_logprob > -1.0:
                    pieces.append(decode_text(tokenizer, result))
                seek += size

            text = " ".join(p for p in pieces if p).strip()
            emit({
                "ok": True,
                "text": text,
                "language": detected,
                "elapsed": round(time.time() - started, 3),
            })
        except Exception as exc:  # noqa: BLE001
            emit({"ok": False, "error": f"{type(exc).__name__}: {exc}"})
            traceback.print_exc(file=sys.stderr)

    return 0


def decode_text(tokenizer, result: DecodingResult) -> str:
    tokens = [t for t in result.tokens if t < tokenizer.eot]
    return tokenizer.decode(tokens).strip()


if __name__ == "__main__":
    sys.exit(main())
