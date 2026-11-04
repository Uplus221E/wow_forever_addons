#!/usr/bin/env python3
"""
clip_watcher.py - Zero-Effort OBS Content & Thumbnail Pipeline
Part of the Vanguard WoW: Forever Command Suite.

Watches C:/WoWClips for OBS Replay Buffer MP4s (triggered via G600 G-Shift + 12).
Extracts action frame via ffmpeg, generates high-CTR 1280x720 YouTube thumbnail
with Pillow, moves assets to Processed/, and creates upload-ready metadata JSON.
"""

import os
import sys
import time
import json
import shutil
import argparse
import subprocess
from pathlib import Path
from datetime import datetime

# Optional 3rd party imports with graceful stdlib fallback
try:
    from PIL import Image, ImageDraw, ImageFont, ImageFilter
    HAS_PILLOW = True
except ImportError:
    HAS_PILLOW = False

try:
    from watchdog.observers import Observer
    from watchdog.events import FileSystemEventHandler
    HAS_WATCHDOG = True
except ImportError:
    HAS_WATCHDOG = False

HOOK_ROTATION = [
    "UNCONTESTED ECONOMY & GOLD ROAD",
    "MEGA-SERVER WORLD PVP HIGHLIGHT",
    "FRESH 60 PIONEER RUN"
]

DEFAULT_WATCH_DIR = Path("C:/WoWClips")
hook_index = 0


def get_default_font(size: int):
    """Attempt to load a crisp standard font with graceful fallback to PIL default."""
    if not HAS_PILLOW:
        return None
    font_candidates = [
        "C:/Windows/Fonts/impact.ttf",
        "C:/Windows/Fonts/arialbd.ttf",
        "C:/Windows/Fonts/segoeuib.ttf",
        "C:/Windows/Fonts/arial.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
    ]
    for font_path in font_candidates:
        if os.path.exists(font_path):
            try:
                return ImageFont.truetype(font_path, size)
            except Exception:
                continue
    return ImageFont.load_default()


def find_ffmpeg() -> str | None:
    """Detect ffmpeg in PATH or standard installation directories."""
    path = shutil.which("ffmpeg")
    if path:
        return path
    candidates = [
        Path("C:/Program Files/ffmpeg/bin/ffmpeg.exe"),
        Path("C:/ffmpeg/bin/ffmpeg.exe"),
        Path("C:/ProgramData/chocolatey/bin/ffmpeg.exe"),
        Path(os.environ.get("LOCALAPPDATA", "")) / "Microsoft/WinGet/Links/ffmpeg.exe"
    ]
    for c in candidates:
        if c.exists():
            return str(c)
    return None


def extract_video_frame(video_path: Path, output_frame_path: Path, ffmpeg_bin: str | None) -> bool:
    """Extract an action frame around 15s or 30% duration using ffmpeg."""
    if not ffmpeg_bin:
        return False
    try:
        # First attempt extraction at 15s
        cmd = [
            ffmpeg_bin,
            "-y",
            "-ss", "00:00:15",
            "-i", str(video_path),
            "-vframes", "1",
            "-q:v", "2",
            str(output_frame_path)
        ]
        result = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=15)
        if result.returncode == 0 and output_frame_path.exists() and output_frame_path.stat().st_size > 0:
            return True

        # Fallback to 3s if clip is short
        cmd[2] = "00:00:03"
        result = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=15)
        return result.returncode == 0 and output_frame_path.exists() and output_frame_path.stat().st_size > 0
    except Exception as e:
        print(f"[-] ffmpeg extraction error: {e}")
        return False


def draw_text_with_outline(draw, position, text, font, fill_color, outline_color, outline_width=4):
    """Draw text with a heavy, readable contrasting outline for maximum CTR."""
    x, y = position
    for dx in range(-outline_width, outline_width + 1):
        for dy in range(-outline_width, outline_width + 1):
            if dx != 0 or dy != 0:
                draw.text((x + dx, y + dy), text, font=font, fill=outline_color)
    draw.text((x, y), text, font=font, fill=fill_color)


def generate_thumbnail(base_image_path: Path | None, output_thumb_path: Path, bottom_hook: str):
    """Render a high-CTR 1280x720 YouTube thumbnail with top/bottom banners."""
    if not HAS_PILLOW:
        print("[-] Pillow is not installed. Skipping thumbnail generation.")
        return False

    width, height = 1280, 720
    if base_image_path and base_image_path.exists():
        try:
            img = Image.open(base_image_path).convert("RGBA")
            img = img.resize((width, height), Image.Resampling.LANCZOS)
        except Exception:
            img = Image.new("RGBA", (width, height), (15, 23, 42, 255))
    else:
        # Create dark atmospheric backdrop if no video frame was extracted
        img = Image.new("RGBA", (width, height), (10, 15, 26, 255))
        gradient = Image.new("RGBA", (width, height), (0, 0, 0, 0))
        g_draw = ImageDraw.Draw(gradient)
        # Deep blue/gold radial aura
        for r in range(400, 0, -10):
            alpha = int(60 * (1 - r / 400))
            g_draw.ellipse(
                (width // 2 - r, height // 2 - r, width // 2 + r, height // 2 + r),
                fill=(30, 64, 175, alpha)
            )
        img = Image.alpha_composite(img, gradient)

    # Vignette overlay for text contrast (dark bars at top and bottom)
    vignette = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    v_draw = ImageDraw.Draw(vignette)
    top_bar_height = 140
    bottom_bar_height = 160

    for y in range(top_bar_height):
        alpha = int(220 * (1 - y / top_bar_height))
        v_draw.line([(0, y), (width, y)], fill=(0, 0, 0, alpha))

    for y in range(bottom_bar_height):
        alpha = int(240 * (y / bottom_bar_height))
        v_draw.line([(0, height - bottom_bar_height + y), (width, height - bottom_bar_height + y)], fill=(0, 0, 0, alpha))

    img = Image.alpha_composite(img, vignette)
    draw = ImageDraw.Draw(img)

    # Fonts
    top_font = get_default_font(52)
    bottom_font = get_default_font(58)
    sub_font = get_default_font(26)

    # Top Banner: WOW FOREVER: VANGUARD SPRINT
    top_text = "WOW FOREVER: VANGUARD SPRINT"
    try:
        bbox_top = draw.textbbox((0, 0), top_text, font=top_font)
        text_w_top = bbox_top[2] - bbox_top[0]
    except Exception:
        text_w_top = len(top_text) * 28
    top_x = (width - text_w_top) // 2
    top_y = 35

    draw_text_with_outline(
        draw=draw,
        position=(top_x, top_y),
        text=top_text,
        font=top_font,
        fill_color="#FFE500",      # High-contrast Golden Yellow
        outline_color="#000000",   # Solid Black Outline
        outline_width=4
    )

    # Decorative accent line under top banner
    line_w = 400
    line_x = (width - line_w) // 2
    draw.rectangle([line_x, top_y + 64, line_x + line_w, top_y + 68], fill="#FFE500")

    # Bottom Banner: Dynamic Hook
    try:
        bbox_bot = draw.textbbox((0, 0), bottom_hook, font=bottom_font)
        text_w_bot = bbox_bot[2] - bbox_bot[0]
    except Exception:
        text_w_bot = len(bottom_hook) * 32
    bot_x = (width - text_w_bot) // 2
    bot_y = height - 125

    draw_text_with_outline(
        draw=draw,
        position=(bot_x, bot_y),
        text=bottom_hook,
        font=bottom_font,
        fill_color="#FFFFFF",      # Pure White
        outline_color="#000000",   # Solid Black Outline
        outline_width=5
    )

    # Small Sub-badge
    badge_text = "4K 60FPS | GNOME MAGE SPEEDRUN"
    try:
        bbox_sub = draw.textbbox((0, 0), badge_text, font=sub_font)
        sub_w = bbox_sub[2] - bbox_sub[0]
    except Exception:
        sub_w = len(badge_text) * 14
    sub_x = (width - sub_w) // 2
    draw_text_with_outline(
        draw=draw,
        position=(sub_x, height - 45),
        text=badge_text,
        font=sub_font,
        fill_color="#38BDF8",      # Bright Cyan / Frost
        outline_color="#000000",
        outline_width=3
    )

    # Final RGB save
    final_rgb = img.convert("RGB")
    final_rgb.save(output_thumb_path, "JPEG", quality=95)
    return True


def select_hook(clip_name: str) -> str:
    """Select the best hook based on filename or rotate sequentially."""
    global hook_index
    lower = clip_name.lower()
    if "pvp" in lower or "kill" in lower or "gank" in lower:
        return "MEGA-SERVER WORLD PVP HIGHLIGHT"
    if "gold" in lower or "snipe" in lower or "rich" in lower or "thorium" in lower or "dme" in lower:
        return "UNCONTESTED ECONOMY & GOLD ROAD"
    if "60" in lower or "ding" in lower or "level" in lower or "speed" in lower:
        return "FRESH 60 PIONEER RUN"

    selected = HOOK_ROTATION[hook_index % len(HOOK_ROTATION)]
    hook_index += 1
    return selected


def wait_for_file_settled(file_path: Path, max_wait: int = 15) -> bool:
    """Wait until file size stops growing (OBS Replay Buffer write complete)."""
    last_size = -1
    for _ in range(max_wait):
        if not file_path.exists():
            return False
        try:
            current_size = file_path.stat().st_size
            if current_size > 0 and current_size == last_size:
                # Try opening exclusively to confirm release
                with open(file_path, "rb"):
                    return True
            last_size = current_size
        except OSError:
            pass
        time.sleep(1)
    return file_path.exists() and file_path.stat().st_size > 0


def process_clip(clip_path: Path, watch_dir: Path, processed_dir: Path, ffmpeg_bin: str | None, dry_run: bool = False):
    """Process a single MP4 clip: extract frame, generate thumb, write metadata, move."""
    print(f"\n[*] New clip detected: {clip_path.name}")
    if not wait_for_file_settled(clip_path):
        print(f"[-] Clip {clip_path.name} was not completely written. Skipping.")
        return

    clip_stem = clip_path.stem
    hook = select_hook(clip_stem)
    thumb_name = f"{clip_stem}_thumb.jpg"
    meta_name = f"{clip_stem}_meta.json"

    temp_frame = watch_dir / f"__temp_{clip_stem}.jpg"
    dest_thumb = processed_dir / thumb_name
    dest_clip = processed_dir / clip_path.name
    dest_meta = processed_dir / meta_name

    if dry_run:
        print(f"[DRY-RUN] Would process {clip_path.name} with hook: '{hook}'")
        print(f"[DRY-RUN] Destination: {dest_clip}")
        return

    # 1. Frame extraction
    has_frame = extract_video_frame(clip_path, temp_frame, ffmpeg_bin)
    if has_frame:
        print(f"[+] Frame extracted successfully via ffmpeg.")
    else:
        print(f"[i] Using high-CTR procedural backdrop (ffmpeg frame not available).")

    # 2. Thumbnail generation
    success = generate_thumbnail(
        base_image_path=temp_frame if has_frame else None,
        output_thumb_path=dest_thumb,
        bottom_hook=hook
    )
    if success:
        print(f"[+] YouTube thumbnail rendered -> {dest_thumb.name}")

    # Clean temporary frame
    if temp_frame.exists():
        temp_frame.unlink(missing_ok=True)

    # 3. Metadata generation
    metadata = {
        "title": f"WoW: Forever - {hook} | Vanguard Gnome Mage Sprint",
        "description": (
            f"Alliance Gnome Frost Mage launch sprint on World of Warcraft: Forever.\n\n"
            f"Hook: {hook}\n"
            f"Automated bank alt logistics, uncontested early node sweeping, and 1-and-done custom dungeon progression.\n\n"
            f"Recorded via OBS Replay Buffer | Generated by Vanguard Forever Command Center."
        ),
        "tags": [
            "WoW", "World of Warcraft", "WoW Forever", "Classic Era", "Gnome Mage",
            "Gold Farming", "Speedrun", "PvP", "TSM", "Vanguard"
        ],
        "clip_file": clip_path.name,
        "thumbnail_file": thumb_name,
        "processed_at": datetime.now().isoformat(),
        "youtube_upload_status": "READY_FOR_UPLOAD"
    }

    # YouTube Data API hook stub
    client_secrets = watch_dir / "client_secrets.json"
    if client_secrets.exists():
        metadata["youtube_auth_available"] = True
        print(f"[+] client_secrets.json found. Ready for YouTube API v3 auto-upload.")

    with open(dest_meta, "w", encoding="utf-8") as f:
        json.dump(metadata, f, indent=2)
    print(f"[+] Metadata saved -> {dest_meta.name}")

    # 4. Move MP4 to Processed folder
    try:
        shutil.move(str(clip_path), str(dest_clip))
        print(f"[+] Clip moved to -> {dest_clip}")
    except Exception as e:
        print(f"[-] Could not move clip: {e}")


def scan_and_process_once(watch_dir: Path, processed_dir: Path, ffmpeg_bin: str | None, dry_run: bool = False):
    """Scan watch directory for pending MP4s and process them."""
    if not watch_dir.exists():
        print(f"[i] Watch directory {watch_dir} does not exist yet. No pending clips.")
        return 0
    mp4s = [f for f in watch_dir.iterdir() if f.is_file() and f.suffix.lower() == ".mp4" and not f.name.startswith("__")]
    if not mp4s:
        print(f"[i] No pending MP4 clips found in {watch_dir}")
        return 0
    for mp4 in mp4s:
        process_clip(mp4, watch_dir, processed_dir, ffmpeg_bin, dry_run)
    return len(mp4s)


def run_watcher(watch_dir: Path, processed_dir: Path, ffmpeg_bin: str | None):
    """Run continuous directory watcher with watchdog or polling fallback."""
    print("================================================================================")
    print(" WOW: FOREVER MEDIA PIPELINE & OBS REPLAY BUFFER WATCHER")
    print("================================================================================")
    print(f"[+] Watching Directory  : {watch_dir}")
    print(f"[+] Processed Directory : {processed_dir}")
    print(f"[+] ffmpeg Status       : {'Available (' + ffmpeg_bin + ')' if ffmpeg_bin else 'Not Found (Using procedural backdrop)'}")
    print(f"[+] Pillow Status       : {'Available' if HAS_PILLOW else 'Not Installed'}")
    print(f"[+] Watch Engine        : {'watchdog' if HAS_WATCHDOG else 'stdlib directory polling (2s interval)'}")
    print("[+] Hotkey Trigger      : G-Shift + 12 on Logitech G600 saves OBS buffer to WoWClips")
    print("================================================================================")
    print("[*] Listening for new clips... (Press Ctrl+C to stop)")

    if HAS_WATCHDOG:
        class ClipHandler(FileSystemEventHandler):
            def on_created(self, event):
                if not event.is_directory and event.src_path.lower().endswith(".mp4"):
                    p = Path(event.src_path)
                    if not p.name.startswith("__"):
                        process_clip(p, watch_dir, processed_dir, ffmpeg_bin)

        event_handler = ClipHandler()
        observer = Observer()
        observer.schedule(event_handler, str(watch_dir), recursive=False)
        observer.start()
        try:
            while True:
                time.sleep(1)
        except KeyboardInterrupt:
            observer.stop()
        observer.join()
    else:
        # Graceful stdlib polling loop
        known_files = set()
        for f in watch_dir.iterdir():
            if f.is_file() and f.suffix.lower() == ".mp4":
                known_files.add(f.name)
        try:
            while True:
                time.sleep(2)
                for f in watch_dir.iterdir():
                    if f.is_file() and f.suffix.lower() == ".mp4" and not f.name.startswith("__"):
                        if f.name not in known_files:
                            known_files.add(f.name)
                            process_clip(f, watch_dir, processed_dir, ffmpeg_bin)
        except KeyboardInterrupt:
            print("\n[*] Watcher terminated gracefully.")


def main():
    parser = argparse.ArgumentParser(description="OBS Replay Buffer Clip & Thumbnail Watcher")
    parser.add_argument("--watch-dir", type=str, default=str(DEFAULT_WATCH_DIR), help="Directory to watch for MP4 clips")
    parser.add_argument("--dry-run", action="store_true", help="Simulate pipeline without modifying files")
    parser.add_argument("--once", action="store_true", help="Process existing clips once and exit")
    parser.add_argument("--test-generate", action="store_true", help="Generate a sample test thumbnail and metadata to verify PIL rendering")

    args = parser.parse_args()

    watch_dir = Path(args.watch_dir)
    processed_dir = watch_dir / "Processed"

    if not args.dry_run:
        watch_dir.mkdir(parents=True, exist_ok=True)
        processed_dir.mkdir(parents=True, exist_ok=True)

    ffmpeg_bin = find_ffmpeg()

    if args.test_generate:
        print("[*] Generating test verification thumbnail and metadata...")
        test_thumb = processed_dir / "sample_test_thumb.jpg"
        test_meta = processed_dir / "sample_test_meta.json"
        hook = select_hook("sample_speedrun_clip")
        generate_thumbnail(None, test_thumb, hook)
        meta = {
            "title": f"WoW: Forever - {hook} | Test Verification Run",
            "test_run": True,
            "generated_at": datetime.now().isoformat()
        }
        with open(test_meta, "w", encoding="utf-8") as f:
            json.dump(meta, f, indent=2)
        print(f"[OK] Test thumbnail: {test_thumb}")
        print(f"[OK] Test metadata: {test_meta}")
        return

    if args.once:
        scan_and_process_once(watch_dir, processed_dir, ffmpeg_bin, args.dry_run)
        return

    run_watcher(watch_dir, processed_dir, ffmpeg_bin)


if __name__ == "__main__":
    main()
