module heaploop.streams;
import heaploop.looping;
import events;
import duv.c;
import duv.types;
import core.thread;

abstract class Stream {
        alias FiberedEventList!(void, Stream, ubyte[]) readEventList;
    private:
        uv_stream_t * _handle;
        Loop _loop;
        readEventList _readEvent;
        readEventList.Trigger _readTrigger;

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

        readEventList read() {
            _readEvent = new readEventList;
            _readTrigger = _readEvent.own((activated) {
                if(activated) {
                    duv_read_start(this.handle, this, function (uv_stream_t * client_conn, Object readContext, size_t nread, ubyte[] data) {
                        Stream thisStream = cast(Stream)readContext;
                        thisStream._readTrigger(thisStream, data);
                        return;
                    });
                } else {
                    duv_read_stop(this.handle);
                }
            });
            return _readEvent;
        }

        class closeContext {
            public Fiber fiber;
            public Stream stream;
        }

        void close() {
            closeContext cx = new closeContext;
            cx.fiber = Fiber.getThis;
            cx.stream = this;
            duv_handle_close(cast(uv_handle_t*)this.handle, cx, function (uv_handle_t * handle, context) {
                    closeContext cx = cast(closeContext)context;
                    cx.fiber.call;
            });
            cx.fiber.yield;
        }

    protected:

        abstract void init();


}
