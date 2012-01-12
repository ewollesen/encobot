.SUFFIXES: .js .coffee
.PHONY: clean

TARGETS = encobot.js \
	  defaults.js \
          industrial_101.js

all: $(TARGETS)

run: all
	node ./encobot.js ./industrial_101.js

clean: 
	-rm -f *.js

.coffee.js: $<
	coffee --compile $<