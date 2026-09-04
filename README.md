# Arix

Arix is a web browser engine written in Zig for the purpose of high performance and minimal memory usage.  <br>

The project currently includes:

- HTML parser
- CSS parser
- A small DOM implementation

**Arix is still under active development. Networking, style engine, layout engine, painting and the browser user interface are not complete yet.**

## Testing

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
