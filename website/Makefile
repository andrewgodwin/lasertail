all: build/lasertail.js

build/lasertail.js: coffee/*.coffee
	mkdir -p build/
	coffee --join build/lasertail.js --compile coffee/
