"""
Script per transcodificare i video esistenti in uploads/videos e uploads/mock_videos
in formato H.264 (AVC1, YUV420p) con atomo moov all'inizio (+faststart).
"""

import os
import subprocess
import glob
import logging

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger(__name__)

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UPLOADS_DIR = os.path.join(BASE_DIR, "uploads")


def transcode_file(filepath: str):
    if not filepath.endswith(".mp4") or "_raw" in filepath:
        return

    # Salta file fittizi / vuoti
    if os.path.getsize(filepath) < 1000:
        logger.info(f"Salto file fittizio/piccolo: {filepath}")
        return

    logger.info(f"Elaborazione: {filepath}")
    temp_out = filepath + ".transcoded.mp4"

    cmd = [
        "ffmpeg",
        "-y",
        "-i", filepath,
        "-c:v", "libx264",
        "-preset", "veryfast",
        "-crf", "23",
        "-pix_fmt", "yuv420p",
        "-movflags", "+faststart",
        "-an",
        temp_out,
    ]

    try:
        res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
        if res.returncode == 0 and os.path.exists(temp_out) and os.path.getsize(temp_out) > 0:
            os.replace(temp_out, filepath)
            logger.info(f"-> Convertito con successo in H.264: {filepath}")
        else:
            if os.path.exists(temp_out):
                os.remove(temp_out)
            logger.error(f"-> Conversione fallita per {filepath}: {res.stderr.decode('utf-8', errors='ignore')[-200:]}")
    except Exception as e:
        if os.path.exists(temp_out):
            os.remove(temp_out)
        logger.error(f"Errore su {filepath}: {e}")


def main():
    target_dirs = [
        os.path.join(UPLOADS_DIR, "videos"),
        os.path.join(UPLOADS_DIR, "mock_videos"),
    ]

    for d in target_dirs:
        if not os.path.exists(d):
            continue
        files = glob.glob(os.path.join(d, "*.mp4"))
        for f in files:
            transcode_file(f)


if __name__ == "__main__":
    main()
