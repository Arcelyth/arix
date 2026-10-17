.PHONY: fetch test_token test_tree

ARIX_HTML_BENCH_DIR := res/bench/html
ARIX_HTML_BENCH_FILES := $(wildcard $(ARIX_HTML_BENCH_DIR)/*.html)

fetch: 
	rm -rf ./zig-pkg
	zig fetch --save=strale "https://github.com/Arcelyth/strale/archive/main.tar.gz"
	zig fetch --save=core_foundation_zig "https://codeberg.org/Arcelyth/core-foundation-zig/archive/main.tar.gz"
	zig fetch --save=dwrite_zig "https://github.com/Arcelyth/dwrite-zig/archive/main.tar.gz"

test_token: 
	zig build test --summary all -Dtest-filter=tokenizer

test_tree: 
	zig build test --summary all -Dtest-filter=tree_construction

test_css: 
	zig build test --summary all -Dtest-filter=CSS

test_enc: 
	zig build test --summary all -Dtest-filter=encoding 

bench_css:
	zig build bench -- --iterations 100 res/bench/css/bench.css

bench_html:
	zig build bench -- --iterations 100 $(ARIX_HTML_BENCH_FILES)
