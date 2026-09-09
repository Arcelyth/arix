.PHONY: fetch test_token test_tree

fetch: 
	rm -rf ./zig-pkg
	zig fetch --save=strale "https://github.com/Arcelyth/strale/archive/main.tar.gz"

test_token: 
	zig build test --summary all -- tokenizer 

test_tree: 
	zig build test --summary all -- tree_construction

test_css: 
	zig build test --summary all -- CSS 

bench_html:
	zig build bench -- --iterations 100 res/bench/html/bench.html

bench_css:
	zig build bench -- --iterations 100 res/bench/css/bench.css

bench_html_unquoted_attr:
	zig build bench -- --iterations 100 res/bench/html/unquoted-attr-value.html
