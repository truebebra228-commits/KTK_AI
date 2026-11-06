"""Fetch only Godot's small web template from the 1.28 GB template archive.

Uses HTTP byte ranges and zipfile's central-directory reader. The member's ZIP
CRC is checked during extraction. No third-party Python packages are required.
"""

from __future__ import annotations

import argparse
import io
from pathlib import Path
import urllib.request
import zipfile


URL = "https://github.com/godotengine/godot/releases/download/4.7.2-stable/Godot_v4.7.2-stable_export_templates.tpz"
ARCHIVE_SIZE = 1_281_349_702
MEMBER = "templates/web_nothreads_release.zip"


class RangeFile(io.RawIOBase):
    def __init__(self) -> None:
        self.position = 0
        self.downloaded = 0

    def seekable(self) -> bool:
        return True

    def readable(self) -> bool:
        return True

    def tell(self) -> int:
        return self.position

    def seek(self, offset: int, whence: int = io.SEEK_SET) -> int:
        if whence == io.SEEK_END:
            offset += ARCHIVE_SIZE
        elif whence == io.SEEK_CUR:
            offset += self.position
        self.position = offset
        return offset

    def read(self, size: int = -1) -> bytes:
        size = min(ARCHIVE_SIZE - self.position, size if size >= 0 else ARCHIVE_SIZE)
        if size <= 0:
            return b""
        request = urllib.request.Request(URL, headers={
            "Range": f"bytes={self.position}-{self.position + size - 1}",
            "User-Agent": "IMPULSE-web-template-builder",
        })
        with urllib.request.urlopen(request, timeout=60) as response:
            if response.status != 206:
                raise RuntimeError(f"Server did not honor the byte range: {response.status}")
            data = response.read(size + 1)
        if len(data) != size:
            raise RuntimeError(f"Short range download: expected {size}, got {len(data)}")
        self.position += size
        self.downloaded += size
        return data


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path,
                        default=Path(__file__).resolve().parents[2] / ".codex-tmp/godot/web_nothreads_release.zip")
    args = parser.parse_args()
    remote = RangeFile()
    with zipfile.ZipFile(remote) as archive:
        data = archive.read(MEMBER)
    # Confirm that the resulting nested template is itself a valid ZIP.
    with zipfile.ZipFile(io.BytesIO(data)) as template:
        if "godot.wasm" not in template.namelist() or template.testzip() is not None:
            raise RuntimeError("Downloaded web template failed verification.")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(data)
    print(f"Saved {args.output}: {len(data):,} bytes; downloaded {remote.downloaded:,} archive bytes.")


if __name__ == "__main__":
    main()
