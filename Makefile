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
