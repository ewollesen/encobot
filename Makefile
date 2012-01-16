.SUFFIXES: .js .coffee
.PHONY: clean

TARGETS = encobot.js \
	  defaults.js \
          industrial_101.js

run:
	coffee ./encobot.coffee ./industrial_101.coffee

all: compile

compile: $(TARGETS)

clean:
	-rm -f *.js

.coffee.js: $<
	coffee --compile $<