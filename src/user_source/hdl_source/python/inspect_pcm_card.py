"""只读核验 FAT32 根目录单个 PCM 文件的整卡 LBA、连续性和内容。"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess


def inspect(letter):
    if len(letter) != 1 or not letter.isascii() or not letter.isalpha():
        raise ValueError('盘符必须是单个英文字母')
    letter = letter.upper()
    files = list(Path(letter + ':/').glob('*.pcm'))
    if len(files) != 1:
        raise ValueError('根目录应恰好有一个 PCM 文件，以免选错音频')
    source = files[0]
    size = source.stat().st_size
    if not size or size % 2:
        raise ValueError('PCM 大小必须是非零偶数字节')
    command = f'Get-Partition -DriveLetter {letter} | Select-Object DiskNumber,Offset,Size | ConvertTo-Json -Compress'
    result = subprocess.run(['powershell.exe', '-NoProfile', '-Command', command],
                            capture_output=True, check=True, text=True)
    partition = json.loads(result.stdout)
    offset = partition['Offset']
    if offset % 512:
        raise ValueError('分区偏移不符合 512 字节扇区要求')
    with open('\\\\.\\' + letter + ':', 'rb', buffering=0) as card:
        def sector(lba):
            if lba < 0 or lba * 512 >= partition['Size']:
                raise ValueError('扇区超出分区范围')
            card.seek(lba * 512)
            data = card.read(512)
            if len(data) != 512:
                raise ValueError('扇区短读')
            return data
        def u32(data, pos):
            return struct.unpack_from('<I', data, pos)[0]
        bpb = sector(0)
        if bpb[510:] != b'\x55\xaa' or struct.unpack_from('<H', bpb, 11)[0] != 512:
            raise ValueError('不支持的引导扇区')
        spc = bpb[13]
        reserved = struct.unpack_from('<H', bpb, 14)[0]
        fat_size = u32(bpb, 36)
        data_start = reserved + bpb[16] * fat_size
        root = u32(bpb, 44)
        max_cluster = (u32(bpb, 32) - data_start) // spc + 1
        def chain(first):
            seen = set()
            clusters = []
            current = first
            while current < 0xffffff8:
                if current < 2 or current > max_cluster or current in seen:
                    raise ValueError('FAT 簇链越界或循环')
                seen.add(current)
                clusters.append(current)
                entry = current * 4
                current = u32(sector(reserved + entry // 512), entry % 512) & 0xfffffff
            return clusters
        matches = []
        directory_end = False
        for cluster in chain(root):
            for index in range(spc):
                data = sector(data_start + (cluster - 2) * spc + index)
                for pos in range(0, 512, 32):
                    entry = data[pos:pos + 32]
                    if entry[0] == 0:
                        directory_end = True
                        break
                    if entry[0] == 0xe5 or entry[11] & 0x18 or entry[11] == 0x0f:
                        continue
                    if entry[8:11] == b'PCM' and u32(entry, 28) == size:
                        first = (struct.unpack_from('<H', entry, 20)[0] << 16) | struct.unpack_from('<H', entry, 26)[0]
                        matches.append(first)
                if directory_end:
                    break
            if directory_end:
                break
        if len(matches) != 1:
            raise ValueError('无法唯一匹配 PCM 目录项')
        clusters = chain(matches[0])
        if len(clusters) != (size + spc * 512 - 1) // (spc * 512):
            raise ValueError('文件大小和簇链长度不匹配')
        if any(b != a + 1 for a, b in zip(clusters, clusters[1:])):
            raise ValueError('音频文件存在碎片，固定 LBA 播放器不能安全播放此文件')
        start = data_start + (clusters[0] - 2) * spc
        digest = hashlib.sha256()
        with source.open('rb') as normal:
            remaining = size
            for index in range((size + 511) // 512):
                payload = sector(start + index)[:min(remaining, 512)]
                if payload != normal.read(len(payload)):
                    raise ValueError('原始扇区内容与 PCM 文件不一致')
                digest.update(payload)
                remaining -= len(payload)
        return {'file': str(source), 'bytes': size, 'sha256': digest.hexdigest(),
                'partition_offset_bytes': offset, 'bpb_hidden_sectors': u32(bpb, 28),
                'volume_relative_lba': start, 'AUDIO_START_LBA': offset // 512 + start,
                'AUDIO_TOTAL_SECTORS': (size + 511) // 512,
                'contiguous_clusters': len(clusters), 'content_verified': True}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('drive', help='TF 卡盘符，例如 G')
    args = parser.parse_args()
    print(json.dumps(inspect(args.drive.rstrip(':')), ensure_ascii=False, indent=2))
