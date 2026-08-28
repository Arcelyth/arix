# Arix

Arix is an HTML parser written in Zig for the purpose of high performance and minimal memory usage. It currently includes an encoding
sniffer, an HTML tokenizer, a TreeBuilder for tree construction, and a small DOM implementation.
Parser behavior is tested against the [html5lib test suite](https://github.com/html5lib/html5lib-tests).

Build and run the test: 
```sh
zig build test
```

You can add `debug` flag to show the debug informations. <br>
Add `-- [test_name]` to filter tests. <br>
For example: `zig build test --summary all -- tokenizer`.
