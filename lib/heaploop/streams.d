module heaploop.streams;
import heaploop.looping;
import events;
import duv.c;
import duv.types;
import core.thread;

abstract class Stream : Looper {
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

        void write(ubyte[] data) {
            auto wc = new OperationContext!Stream(this);
            duv_write(this.handle, wc, data, function (uv_stream_t * thisHandle, contextObj, status writeStatus) {
                    auto wc = cast(OperationContext!Stream)contextObj;
                    wc.resume(writeStatus);
            });
            wc.yield;
            wc.completed;
        }

        readEventList read() {
            _readEvent = new readEventList;
            _readTrigger = _readEvent.own((activated) {
                auto rx = new OperationContext!Stream(this);
                if(activated) {
                    duv_read_start(this.handle, rx, function (uv_stream_t * client_conn, Object readContext, ptrdiff_t nread, ubyte[] data) {
                        std.stdio.writeln("read %d", nread, data);
                        auto rx = cast(OperationContext!Stream)readContext;
                        Stream thisStream = rx.target;
                        int status = cast(int)nread;
                        if(status.isError) {
                            rx.resume(status);
                        } else {
                            thisStream._readTrigger(thisStream, data);
                        }
                    });
                    rx.yield;
                    rx.completed;
                } else {
                    duv_read_stop(this.handle);
                }
            });
            return _readEvent;
        }

        void close() {
            auto cx = new OperationContext!Stream(this);
            duv_handle_close(cast(uv_handle_t*)this.handle, cx, function (uv_handle_t * handle, context) {
                    auto cx = cast(OperationContext!Stream)context;
                    cx.resume;
            });
            cx.yield;
            cx.completed;
        }

    protected:

        abstract void init();


}
