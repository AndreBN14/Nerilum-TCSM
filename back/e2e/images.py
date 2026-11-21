import struct
import zlib


def chunk(tag, data):
    return (
        struct.pack(">I", len(data))
        + tag
        + data
        + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    )


def make_png(width=32, height=32, rgb=(128, 128, 128)):
    raw = bytearray()
    for _ in range(height):
        raw.append(0)
        raw.extend(bytes(rgb) * width)
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )


def load_image(config):
    if config.image_path:
        with open(config.image_path, "rb") as handle:
            return handle.read()
    return make_png()
