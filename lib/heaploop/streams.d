module heaploop.streams;
import heaploop.looping;
import duv.c;
import duv.types;
import core.thread;

abstract class Stream {
    private:
        uv_stream_t * _handle;
        Loop _loop;

    public:

        this(Loop loop, uv_handle_type type) {
            import std.c.stdlib : malloc;
            _loop = loop;
            _handle = cast(uv_stream_t*)malloc(uv_handle_size(type));
            this.init();
        }

        @property Loop loop() {
            return _loop;
        }

        @property uv_stream_t* handle() {
            return _handle;
        }

        class writeContext {
            public Fiber fiber;
            public Stream stream;
        }

        void write(ubyte[] data) {
            auto wc = new writeContext;
            wc.fiber = Fiber.getThis;
            wc.stream = this;
            duv_write(this.handle, wc, data, function (uv_stream_t * thisHandle, contextObj, status writeStatus) {
                    writeStatus.check();
                    writeContext wc = cast(writeContext)contextObj;
                    wc.fiber.call;
            });
            wc.fiber.yield;
        }

    protected:

        abstract void init();


}
