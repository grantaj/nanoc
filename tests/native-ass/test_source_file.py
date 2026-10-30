#!/usr/bin/env python3
"""Source-file stack tests against both real C assemblers.

No duplicate parser or assembler. The host I/O adapter is the only test
shim; source text and include files are always consumed by compiled C.
"""
import ctypes
import tempfile
from pathlib import Path

from test_instruction_value import compile_assembler, ROOT


def assemble(lib, source, directory=b""):
    name = str(source).encode("ascii")
    code = lib.ass_assemble(name, len(name), directory, len(directory), 0)
    length = ctypes.c_int.in_dll(lib, "ass_image_length").value
    image = bytes((ctypes.c_ubyte * 11264).in_dll(lib, "ass_image"))[:length]
    depth = ctypes.c_int.in_dll(lib, "source_depth").value
    return code, image, depth


def verify_closed(lib, sample):
    name = str(sample).encode("ascii")
    lib.io_open.argtypes = [ctypes.c_char_p, ctypes.c_int]
    lib.io_open.restype = ctypes.c_int
    lib.io_close.argtypes = [ctypes.c_int]
    lib.io_close.restype = ctypes.c_ubyte
    opened = []
    for _ in range(5):
        handle = lib.io_open(name, len(name))
        assert handle > 0, ("leaked input handle", opened, handle)
        opened.append(handle)
    assert lib.io_open(name, len(name)) < 0
    for handle in opened:
        assert lib.io_close(handle) == 0


def cases():
    # name: root, included files, expected status, successful result bytes
    return {
        "empty_root": (b"", {}, 0, b""),
        "root_no_eol": (b"* = $0800\nbyte 7", {}, 0, b"\x07"),
        "root_final_include": (
            b'* = $0800\nbyte 1\ninclude "a.asm"',
            {"a.asm": b"byte 2"}, 0, b"\x01\x02"
        ),
        "nested_final_includes": (
            b'* = $0800\ninclude "a.asm"',
            {"a.asm": b'byte 1\ninclude "b.asm"',
             "b.asm": b"byte 2"}, 0, b"\x01\x02"
        ),
        "nested_newlines": (
            b'* = $0800\r\nbyte 1\r\ninclude "a.asm"\r\nbyte 4\r\n',
            {"a.asm": b'byte 2\rinclude "b.asm"\rbyte 3\r',
             "b.asm": b"byte 9\n"}, 0, b"\x01\x02\x09\x03\x04"
        ),
        "empty_child": (
            b'* = $0800\ninclude "a.asm"\nbyte 9\n',
            {"a.asm": b""}, 0, b"\x09"
        ),
        "repeated_child": (
            b'* = $0800\ninclude "a.asm"\ninclude "a.asm"\nbyte 3',
            {"a.asm": b"byte 1\n"}, 0, b"\x01\x01\x03"
        ),
        "root_and_child_pending": (
            b'* = $0800\ninclude "a.asm"',
            {"a.asm": b'include "b.asm"',
             "b.asm": b"byte 55"}, 0, b"\x37"
        ),
        "maximum_depth": (
            b'* = $0800\ninclude "a.asm"',
            {"a.asm": b'include "b.asm"',
             "b.asm": b'include "c.asm"',
             "c.asm": b'include "d.asm"',
             "d.asm": b"byte 5"}, 0, b"\x05"
        ),
        "too_deep": (
            b'* = $0800\ninclude "a.asm"',
            {"a.asm": b'include "b.asm"',
             "b.asm": b'include "c.asm"',
             "c.asm": b'include "d.asm"',
             "d.asm": b'include "e.asm"',
             "e.asm": b"byte 5"}, 14, b""
        ),
        "missing_child": (
            b'* = $0800\nbyte 1\ninclude "missing.asm"\n',
            {}, 12, b""
        ),
        "invalid_include": (
            b'* = $0800\ninclude noquotes\n',
            {}, 1, b""
        ),
        "child_line_overflow": (
            b'* = $0800\ninclude "a.asm"\n',
            {"a.asm": b";" + b"z" * 255 + b"\n"}, 13, b""
        ),
        "child_parse_error": (
            b'* = $0800\ninclude "a.asm"\nbyte 3',
            {"a.asm": b"not_an_instruction\n"}, 5, b""
        ),
        "child_include_empty": (
            b'* = $0800\ninclude "a.asm"\nbyte 1',
            {"a.asm": b'include "b.asm"', "b.asm": b""}, 0, b"\x01"
        ),
        "global_forward_across_include": (
            b'* = $0800\nword tail\ninclude "a.asm"\ntail: rts',
            {"a.asm": b"byte $ab\n"}, 0, b"\x03\x08\xab\x60"
        ),
    }


def run():
    with tempfile.TemporaryDirectory(prefix="native_source_io_") as temp:
        folder = Path(temp)
        old = compile_assembler(ROOT, folder / "original.so", 0)
        new = compile_assembler(ROOT, folder / "native.so", 1)
        fixture_dir = folder / "sources"
        fixture_dir.mkdir()
        prefix = (str(fixture_dir) + "/").encode("ascii")

        for label, (root, children, expected, expected_image) in cases().items():
            root_path = fixture_dir / "root.asm"
            root_path.write_bytes(root)
            for child in fixture_dir.glob("*.asm"):
                if child != root_path:
                    child.unlink()
            for name, data in children.items():
                (fixture_dir / name).write_bytes(data)
            baseline = assemble(old, root_path, prefix)
            candidate = assemble(new, root_path, prefix)
            assert baseline[0] == candidate[0] == expected, (label, baseline, candidate)
            if expected == 0:
                assert baseline[1] == candidate[1] == expected_image, (
                    label, baseline[1].hex(), candidate[1].hex(), expected_image.hex()
                )
            assert candidate[2] == -1, (label, candidate)
            verify_closed(new, root_path)
            verify_closed(old, root_path)

        # Exercise zero-copy include names with an empty source-directory.
        child_path = fixture_dir / "absolute.asm"
        child_path.write_bytes(b"byte 12")
        root_path = fixture_dir / "root.asm"
        root_path.write_bytes(
            b"* = $0800\ninclude \"" + str(child_path).encode() + b"\""
        )
        baseline = assemble(old, root_path)
        candidate = assemble(new, root_path)
        assert baseline[:2] == candidate[:2] == (0, b"\x0c"), (
            "absolute_include", baseline, candidate
        )

        print("PASS 17 source-file stack, EOF, include and cleanup cases")


if __name__ == "__main__":
    run()
