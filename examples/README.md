# Examples

Run an example by name from the repository root, for example:

```sh
zig build example:rect
```

Each example runs from `examples/<name>/`, so its input and output paths are
relative to that directory. 

The `rect` example draws six colored rectangles including two of which are nested inside a padded rectangle and outputs the rendering result as a PPM image in the `target/` folder.
