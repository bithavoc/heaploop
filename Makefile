DC=dmd
OS_NAME=$(shell uname -s)
MH_NAME=$(shell uname -m)
#DFLAGS=-debug -gc -gs -g
ifeq (${OS_NAME},Darwin)
	DFLAGS+=-L-framework -LCoreServices 
endif
lib_build_params=../out/heaploop.o ../out/duv.a ../out/uv.a ../out/events.d.a ../out/http-parser.a -I../out/di

build: heaploop

examples: heaploop
	cd examples; $(DC) -of../out/loop_example loop_example.d $(lib_build_params) $(DFLAGS)
	cd examples; $(DC) -of../out/http_example http_example.d $(lib_build_params) $(DFLAGS)

heaploop: lib/**/*.d deps/duv deps/events.d deps/http-parser.d
	mkdir -p out
	cd lib; $(DC) -Hd../out/di/ -of$(lib_build_params) -op -c heaploop/*.d heaploop/networking/*.d $(lib_build_params) $(DFLAGS)
	ar -r out/heaploop.a out/heaploop.o

.PHONY: clean rduv

deps/events.d:
	@echo "Compiling deps/events.d"
	git submodule update --init --recursive --remote deps/events.d
	mkdir -p out
	$(MAKE) -C deps/events.d
	cp deps/events.d/out/events.d.a out/
	cp -r deps/events.d/out/events/* out/di

deps/duv:
	@echo "Compiling deps/duv.d"
	git submodule update --init  --remote deps/duv
	mkdir -p out/di
	(cd deps/duv; $(MAKE) )
	cp deps/duv/out/uv.a out/uv.a
	cp deps/duv/out/duv.a out/duv.a
	cp -r deps/duv/out/di/* out/di

deps/http-parser.d:
	@echo "Compiling deps/http-parser.d"
	git submodule update --init --remote deps/http-parser.d
	mkdir -p out/di
	(cd deps/http-parser.d; $(MAKE) )
	cp deps/http-parser.d/out/http-parser.a out/http-parser.a
	cp -r deps/http-parser.d/out/di/* out/di

rparser: deps/http-parser.d/lib/http/parser/*.d deps/http-parser.d/src/*.c
	mkdir -p out/di
	(cd deps/http-parser.d; $(MAKE) )
	cp deps/http-parser.d/out/http-parser.a out/http-parser.a
	cp -r deps/http-parser.d/out/di/* out/di

clean:
	rm -rf out/*
	rm -rf deps/*
