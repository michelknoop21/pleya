from screenshots import chunks, md5_of


def test_chunks_cover_file(tmp_path):
    f = tmp_path / "a.png"
    f.write_bytes(b"x" * 10_000_001)
    ops = [{"offset": o, "length": l} for o, l in [(0, 5_000_000), (5_000_000, 5_000_000), (10_000_000, 1)]]
    parts = list(chunks(f, ops))
    assert [len(p) for p in parts] == [5_000_000, 5_000_000, 1]


def test_md5_matches_hashlib(tmp_path):
    import hashlib

    f = tmp_path / "b.png"
    f.write_bytes(b"pleya")
    assert md5_of(f) == hashlib.md5(b"pleya").hexdigest()
