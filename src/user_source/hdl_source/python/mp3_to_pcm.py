#!/usr/bin/env python3
"""将 MP3/其他音频转换为第十一讲播放器需要的裸 PCM。"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="使用 FFmpeg 将音频转换为 48 kHz、16 位、单声道、有符号小端裸 PCM"
    )
    parser.add_argument("input", type=Path, nargs="?", help="输入 MP3/WAV 文件")
    parser.add_argument("output", type=Path, nargs="?", help="输出 .pcm 文件，默认与输入同名")
    parser.add_argument("--ffmpeg", default="ffmpeg", help="FFmpeg 可执行文件路径")
    parser.add_argument("--force", action="store_true", help="允许覆盖已存在的输出文件")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.input is None:
        entered = input("请把 MP3/WAV 文件路径粘贴到这里：").strip().strip('"')
        if not entered:
            print("未输入文件，已取消。", file=sys.stderr)
            return 2
        args.input = Path(entered)
    source = args.input.expanduser().resolve()
    target = (args.output or source.with_suffix(".pcm")).expanduser().resolve()

    if not source.is_file():
        print(f"错误：找不到输入文件：{source}", file=sys.stderr)
        return 2
    if source == target:
        print("错误：输入文件和输出文件不能相同。", file=sys.stderr)
        return 2
    if target.exists() and not args.force:
        print(f"错误：输出文件已存在，请改名或使用 --force：{target}", file=sys.stderr)
        return 2

    ffmpeg = shutil.which(args.ffmpeg) or args.ffmpeg
    target.parent.mkdir(parents=True, exist_ok=True)
    command = [
        ffmpeg,
        "-hide_banner",
        "-loglevel",
        "error",
        "-y" if args.force else "-n",
        "-i",
        str(source),
        "-ar",
        "48000",
        "-ac",
        "1",
        "-sample_fmt",
        "s16",
        "-f",
        "s16le",
        str(target),
    ]
    try:
        subprocess.run(command, check=True)
    except FileNotFoundError:
        print("错误：未找到 FFmpeg。请安装 FFmpeg，或用 --ffmpeg 指定其完整路径。", file=sys.stderr)
        return 3
    except subprocess.CalledProcessError as exc:
        print(f"错误：FFmpeg 转换失败，退出码 {exc.returncode}。", file=sys.stderr)
        return exc.returncode or 1

    size = target.stat().st_size
    print(f"转换完成：{target}")
    print("格式：48 kHz / 16 位 / 单声道 / 有符号小端 PCM")
    print(f"大小：{size} 字节，约 {size / (48000 * 2):.2f} 秒")
    print(f"扇区数（向上取整）：{(size + 511) // 512}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
