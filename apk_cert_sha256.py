#!/usr/bin/env python3
"""Print the SHA-256 of an APK's signing certificate (DER), uppercase hex.

Reads the v3 then v2 APK Signing Block, falling back to the v1 JAR signature. This is the
same digest apksigner reports as "certificate SHA-256 digest" and that the framework
compares in PackageUtils.computeSha256Digest(). Written to avoid depending on apksigner,
which needs a JVM, and on keytool, which cannot read v2/v3-only APKs.
"""

import hashlib
import struct
import sys
import zipfile

V2_ID = 0x7109871A
V3_ID = 0xF05368C0
MAGIC = b"APK Sig Block 42"


def _signing_block(data):
    eocd = data.rfind(b"PK\x05\x06")
    if eocd < 0:
        return None
    cd_off = struct.unpack_from("<I", data, eocd + 16)[0]
    if cd_off < 24 or data[cd_off - 16:cd_off] != MAGIC:
        return None
    size = struct.unpack_from("<Q", data, cd_off - 24)[0]
    start = cd_off - 8 - size
    if start < 0 or struct.unpack_from("<Q", data, start)[0] != size:
        return None
    return data[start + 8:cd_off - 24]


def _pairs(block):
    off = 0
    while off + 12 <= len(block):
        length = struct.unpack_from("<Q", block, off)[0]
        if length < 4 or off + 8 + length > len(block):
            break
        yield struct.unpack_from("<I", block, off + 8)[0], block[off + 12:off + 8 + length]
        off += 8 + length


def _u32_prefixed(buf, off):
    """Return (payload, next_offset) for a uint32-length-prefixed field."""
    length = struct.unpack_from("<I", buf, off)[0]
    return buf[off + 4:off + 4 + length], off + 4 + length


def _first_cert(value):
    signers, _ = _u32_prefixed(value, 0)
    signer, _ = _u32_prefixed(signers, 0)
    signed_data, _ = _u32_prefixed(signer, 0)
    _, off = _u32_prefixed(signed_data, 0)          # digests
    certificates, _ = _u32_prefixed(signed_data, off)
    cert, _ = _u32_prefixed(certificates, 0)
    return cert


def _v1_cert(path):
    import re
    with zipfile.ZipFile(path) as z:
        names = [n for n in z.namelist()
                 if re.fullmatch(r"META-INF/.*\.(RSA|DSA|EC)", n, re.IGNORECASE)]
        if not names:
            return None
        pkcs7 = z.read(sorted(names)[0])
    # Pull the first X.509 certificate out of the PKCS#7 container: it is a SEQUENCE
    # whose contents start with a version-tagged [0] element.
    idx = pkcs7.find(b"\x30\x82")
    while idx >= 0:
        length = struct.unpack(">H", pkcs7[idx + 2:idx + 4])[0] + 4
        blob = pkcs7[idx:idx + length]
        if b"\xa0\x03\x02\x01\x02" in blob[:32]:
            return blob
        idx = pkcs7.find(b"\x30\x82", idx + 1)
    return None


def cert_sha256(path):
    with open(path, "rb") as fh:
        data = fh.read()
    block = _signing_block(data)
    if block:
        found = dict(_pairs(block))
        for scheme in (V3_ID, V2_ID):
            if scheme in found:
                try:
                    return hashlib.sha256(_first_cert(found[scheme])).hexdigest().upper()
                except (struct.error, IndexError):
                    continue
    cert = _v1_cert(path)
    if cert:
        return hashlib.sha256(cert).hexdigest().upper()
    return None


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: apk_cert_sha256.py <apk>")
    digest = cert_sha256(sys.argv[1])
    if not digest:
        sys.exit("ERROR: no signing certificate found in %s" % sys.argv[1])
    print(digest)
