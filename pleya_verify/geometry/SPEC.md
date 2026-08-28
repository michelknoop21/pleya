<!-- anti-slop: off -->
# Geometry test vectors

`cases.json` is the shared test-vector file for
`pleya_verify/runner/lib/src/geometry.dart`, read by
`pleya_verify/runner/test/geometry_test.dart`. Modeled on
`docs/pleya-protocol/v1/examples/manifest.json`'s manifest-of-fixtures shape:
one file, one comment, one flat list, so a new vector is a one-line diff.

## Case shape

```json
{"function": "insideViewport", "description": "...", "args": {...}, "expectOk": true}
```

- `function` — the `geometry.dart` top-level function to call.
- `description` — human-readable, shown in the test name.
- `args` — named arguments, shape depends on `function` (below).
- `expectOk` — the expected `GeometryVerdict.ok`.

Rects are always `{"x", "y", "width", "height"}` in logical pixels — the
same shape `/v1/ui_tree`'s `bounds` and `/v1/viewport` use.

## `args` shape per function

| Function | `args` keys |
|---|---|
| `insideViewport` | `rect`, `viewport` |
| `notClipped` | `rect`, `clipBounds` |
| `notOverlapping`, `below`, `above`, `leftOf`, `rightOf` | `a`, `b` |
| `minimumTapTarget` | `rect`, optional `minSize` (default 44.0) |
| `sameRow`, `sameColumn` | `a`, `b`, optional `tolerance` (default 1.0) |

## Adding a vector

Append an entry to `cases`. No registration elsewhere is needed — the test
iterates the whole array and dispatches on `function`. Prefer a boundary
case (an edge touching exactly, a delta exactly at a tolerance) over another
"clearly true"/"clearly false" pair: those are what actually catch an
off-by-one in `<` vs `<=`.
