DC=dmd
OS_NAME=$(shell uname -s)
MH_NAME=$(shell uname -m)
DFLAGS=
ifeq (${DEBUG}, 1)
	DFLAGS=-debug -gc -gs -g
else
	DFLAGS=-O -release -inline -noboundscheck
endif
ifeq (${OS_NAME},Darwin)
	DFLAGS+=-L-framework -LCoreServices 
endif
lib_build_params=../out/heaploop.a -I../out/di

build: heaploop

examples: heaploop
	cd examples; $(DC) -of../out/loop_example loop_example.d $(lib_build_params) $(DFLAGS)
	cd examples; $(DC) -of../out/http_example http_example.d $(lib_build_params) $(DFLAGS)
	cd examples; $(DC) -of../out/tcp_client tcp_client.d $(lib_build_params) $(DFLAGS)
	cd examples; $(DC) -of../out/http_client http_client.d $(lib_build_params) $(DFLAGS)
	cd examples; $(DC) -of../out/http_body http_body.d $(lib_build_params) $(DFLAGS)
	cd examples; $(DC) -of../out/http_serv http_serv.d $(lib_build_params) $(DFLAGS)

heaploop: lib/**/*.d deps
	mkdir -p out
	cd lib; $(DC) -Hd../out/di/ -of../out/heaploop.o -op -c heaploop/*.d heaploop/networking/*.d $(lib_build_params) $(DFLAGS)
	ar -r out/heaploop.a out/heaploop.o out/duv/*.o out/events/*.o out/http-parser/*.o

test: heaploop test/*.d
	mkdir -p out
	cd lib; $(DC) -Hd../out/di/ -of../out/heaploop_runner -op -unittest -main heaploop/*.d heaploop/networking/*.d ../test/*.d -I../out/di $(DFLAGS) ../out/duv/*.o ../out/events/*.o ../out/http-parser/*.o
	out/./heaploop_runner

.PHONY: clean

deps: deps/events.d deps/duv deps/http-parser.d
	(mkdir -p out/duv ; cd out/duv ; ar -x ../duv.a)
	(mkdir -p out/events ; cd out/events ; ar -x ../events.d.a)
	(mkdir -p out/http-parser ; cd out/http-parser ; ar -x ../http-parser.a)

deps/events.d:
	@echo "Compiling deps/events.d"
	git submodule update --init --recursive --remote deps/events.d
	mkdir -p out
	DEBUG=${DEBUG} $(MAKE) -C deps/events.d
	cp deps/events.d/out/events.d.a out/
	cp -r deps/events.d/out/events/* out/di

deps/duv:
	@echo "Compiling deps/duv.d"
	git submodule update --init  --remote deps/duv
	mkdir -p out/di
	(cd deps/duv; DEBUG=${DEBUG} $(MAKE) )
	cp deps/duv/out/uv.a out/uv.a
	cp deps/duv/out/duv.a out/duv.a
	cp -r deps/duv/out/di/* out/di

deps/http-parser.d:
	@echo "Compiling deps/http-parser.d"
	git submodule update --init --remote deps/http-parser.d
	mkdir -p out/di
	(cd deps/http-parser.d; DEBUG=${DEBUG} $(MAKE) )
	cp deps/http-parser.d/out/http-parser.a out/http-parser.a
	cp -r deps/http-parser.d/out/di/* out/di

clean:
	rm -rf out/*
	rm -rf deps/*
