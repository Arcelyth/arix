# Arix

Arix is a web browser engine written in Zig for the purpose of high performance and low memory usage.  <br>

## Status

The project currently includes:

- HTML parser
- CSS engine: parsing, selector matching, cascade, and computed styles
- Text decoding and a basic DOM
- Fonts: loading, matching, and text shaping
- Layout: basic blocks and text wrapping
- Paint: backgrounds, borders, and text

**Arix is still under active development. Styling, layout, and painting are currently partial and incomplete. Networking and the JavaScript engine are not yet implemented.**

## Requirements

Requires Zig 0.17.0.

### Linux
Ensure that `Python 3` is on your machine.

## Examples

```sh
zig build example:<name>
```

See [examples](./examples).

## Testing
Tests cover HTML and CSS parsing, text decoding, DOM, styles, font matching,
shaping, text measurement, line breaks, layout, and painting.
HTML parser's behavior is tested against the [html5lib test suite](https://github.com/html5lib/html5lib-tests).

Build and run the test:
```sh
zig build test
```

Add `-Ddebug=true` for debug output and `--summary all` for a full summary.
Use `-Dtest-filter=<name>` to filter tests.

For example:
```sh
zig build test --summary all -Dtest-filter=tokenizer
```

## Benchmarks

Compiled in `ReleaseFast` mode and run benchmarks:
```sh
zig build bench -- [--iterations N] FILE.html FILE.css ...
```
or you can directly use commands in Makefile:
```sh
make bench_html
make bench_css
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md)
