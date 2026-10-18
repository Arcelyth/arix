# Examples

Run an example by name from the repository root, for example:

```sh
zig build example:textblock
```

Each example runs from `examples/<name>/`, so its input and output paths are
relative to that directory. 

The `textblock` example draws six nested blocks with borders and wrapped text and outputs the rendering result as a BMP format image in the `target/` folder.
The `page` example draws a simple page.
