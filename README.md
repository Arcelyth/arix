# Arix

Arix is a web browser engine written in Zig for the purpose of high performance and minimal memory usage.  <br>

The project currently includes:

- HTML parser
- CSS engine which include CSS parser, CSS matching, cascade, and computed styles
- Text decoding and a basic DOM
- Simple layout and painting

**Arix is still under active development. Styling, layout, and painting are currently partial and incomplete. Networking and the JavaScript engine are not yet implemented.**

## Examples

```sh
zig build example:<name>
```

See [examples](./examples).

## Testing
Tests cover HTML and CSS parsing, text decoding, DOM, styles, and block layout.
HTML parser's behavior is tested against the [html5lib test suite](https://github.com/html5lib/html5lib-tests).

Build and run the test: 
```sh
zig build test
```

You can add `debug` flag to show the debug informations. <br>
Add `-- [test_name]` to filter tests. <br>

For example: 
```sh
zig build test --summary all -- tokenizer
```

## Benchmarks

Compiled in `ReleaseFast` mode and run benchmarks: 
```sh
zig build bench -- [--iterations N] FILE.html FILE.css ...
```
or you can directly use commands in Makefile: 
```sh
make bench_html/bench_css
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md)
