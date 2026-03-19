#!/usr/bin/env python3
"""
Generate 4 PBA training beep WAV files for A/B testing.
Run from repo root: python3 scripts/generate_pba_beeps.py
Output: FootballScanningAI/pba_beep_a.wav, pba_beep_b.wav, pba_beep_c.wav, pba_beep_d.wav
"""
import math
import struct
import wave
from pathlib import Path
from typing import Optional

SAMPLE_RATE = 44100

def tri_phase(phase: float) -> float:
    """Triangle wave: 0->1->0 over 0..1."""
    p = phase % 1.0
    return 2 * p if p < 0.5 else 2 * (1 - p)

def sine_triangle_blend(phase: float, blend: float = 0.15) -> float:
    """Sine with slight triangle blend. blend=0 is pure sine."""
    s = math.sin(2 * math.pi * phase)
    t = tri_phase(phase)
    return s * (1 - blend) + t * blend

def envelope_adsr(
    n: int, total: int, attack_n: int, decay_n: int, release_n: int,
    sustain_level: float = 0.0,
) -> float:
    """Return gain 0..1. Attack -> decay to sustain_level (or 0) -> hold -> release at end."""
    if n < attack_n:
        return n / attack_n if attack_n else 1.0
    if n < total - release_n:
        if decay_n <= 0:
            return 1.0 if sustain_level == 0 else sustain_level
        decay_progress = min(1.0, (n - attack_n) / decay_n)
        level = 1.0 - decay_progress * (1.0 - sustain_level)
        return max(0.0, level)
    # release: fade to 0 over last release_n samples (from sustain_level or decayed level)
    release_progress = (n - (total - release_n)) / release_n if release_n else 1.0
    if sustain_level > 0:
        start_release = sustain_level
    else:
        decay_progress = min(1.0, (total - release_n - 1 - attack_n) / decay_n) if decay_n else 1.0
        start_release = 1.0 - decay_progress
    return max(0.0, start_release * (1.0 - release_progress))

def freq_at_sample(n: int, total: int, f_start: float, f_end: float) -> float:
    """Linear pitch drop from f_start to f_end over duration."""
    if total <= 1:
        return f_start
    t = n / (total - 1)
    return f_start + t * (f_end - f_start)

def two_phase_freq(n: int, total: int, split_n: int, f1: float, f2: float) -> float:
    """First split_n samples at f1, rest at f2 (for Version D)."""
    return f1 if n < split_n else f2

def generate_beep(
    out_path: Path,
    duration_sec: float,
    primary_f_start: float,
    primary_f_end: float,
    secondary_f: float,
    secondary_gain: float,
    attack_sec: float,
    decay_sec: float,
    release_sec: float,
    two_phase_split_sec: Optional[float] = None,
    two_phase_f1: Optional[float] = None,
    sustain_level: float = 0.0,
    level: float = 0.4,
) -> None:
    total_n = int(duration_sec * SAMPLE_RATE)
    attack_n = int(attack_sec * SAMPLE_RATE)
    decay_n = int(decay_sec * SAMPLE_RATE)
    release_n = int(release_sec * SAMPLE_RATE)

    if two_phase_split_sec is not None and two_phase_f1 is not None:
        split_n = int(two_phase_split_sec * SAMPLE_RATE)
        def freq_fn(i, tot):
            return two_phase_freq(i, tot, split_n, two_phase_f1, primary_f_end)
    else:
        def freq_fn(i, tot):
            return freq_at_sample(i, tot, primary_f_start, primary_f_end)

    phase_primary = 0.0
    phase_secondary = 0.0
    samples = []
    for n in range(total_n):
        f_primary = freq_fn(n, total_n)
        f_secondary = secondary_f
        phase_primary += f_primary / SAMPLE_RATE
        phase_secondary += f_secondary / SAMPLE_RATE
        primary = sine_triangle_blend(phase_primary)
        secondary = sine_triangle_blend(phase_secondary) * secondary_gain
        gain = envelope_adsr(n, total_n, attack_n, decay_n, release_n, sustain_level=sustain_level)
        sample = (primary + secondary) * gain * level  # avoid clipping (default 0.4)
        sample = max(-1.0, min(1.0, sample))
        samples.append(sample)

    with wave.open(str(out_path), "wb") as wav:
        wav.setnchannels(1)
        wav.setsampwidth(2)  # 16-bit
        wav.setframerate(SAMPLE_RATE)
        for s in samples:
            wav.writeframes(struct.pack("<h", int(s * 32767)))

def main():
    repo_root = Path(__file__).resolve().parent.parent
    out_dir = repo_root / "FootballScanningAI"
    out_dir.mkdir(parents=True, exist_ok=True)

    # A — Clear & neutral: mid pitch, medium length. Default training cue.
    generate_beep(
        out_dir / "pba_beep_a.wav",
        duration_sec=0.195,
        primary_f_start=1240,
        primary_f_end=1100,
        secondary_f=2200,
        secondary_gain=0.10,
        attack_sec=0.006,
        decay_sec=0.120,
        release_sec=0.025,
        sustain_level=0.65,
        level=0.44,
    )

    # B — Punchy & direct: shorter, brighter. "Go" cue that cuts through.
    generate_beep(
        out_dir / "pba_beep_b.wav",
        duration_sec=0.125,
        primary_f_start=1380,
        primary_f_end=1250,
        secondary_f=2600,
        secondary_gain=0.12,
        attack_sec=0.003,
        decay_sec=0.065,
        release_sec=0.022,
        sustain_level=0.0,
        level=0.46,
    )

    # C — Warm & easy: lower pitch, longer. Softer, less demanding.
    generate_beep(
        out_dir / "pba_beep_c.wav",
        duration_sec=0.250,
        primary_f_start=880,
        primary_f_end=800,
        secondary_f=1650,
        secondary_gain=0.07,
        attack_sec=0.010,
        decay_sec=0.160,
        release_sec=0.030,
        sustain_level=0.55,
        level=0.45,
    )

    # D — Hybrid: familiar training beep (1.1–1.2 kHz) with a subtle signature — slight pitch drop + short shoulder so it’s recognizable but not generic
    generate_beep(
        out_dir / "pba_beep_d.wav",
        duration_sec=0.340,
        primary_f_start=950,
        primary_f_end=1420,
        secondary_f=1900,
        secondary_gain=0.08,
        attack_sec=0.005,
        decay_sec=0.200,
        release_sec=0.035,
        sustain_level=0.0,
        level=0.46,
        two_phase_split_sec=0.120,
        two_phase_f1=950,
    )

    print("Generated:", [str(p) for p in out_dir.glob("pba_beep_*.wav")])

if __name__ == "__main__":
    main()
