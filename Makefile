DC=dmd
lib_build_params=out/heaploop.o out/duv.a out/uv.a out/events.d.a -Iout/di

build: heaploop

examples: heaploop
	$(DC) -debug -g -gc -ofout/loop_example examples/loop_example.d $(lib_build_params)

heaploop: lib/**/*.d deps/duv deps/events.d
	mkdir -p out
	$(DC) -debug -g -gc -Hdout/di/heaploop -of$(lib_build_params) -c lib/heaploop/*.d lib/heaploop/networking/*.d $(lib_build_params)
	ar -r out/heaploop.a out/heaploop.o

.PHONY: clean

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

clean:
	rm -rf out/*
	rm -rf deps/*
