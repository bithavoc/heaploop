module heaploop.streams;
import heaploop.looping;
import events;
import duv.c;
import duv.types;
import core.thread;
debug {
    import std.stdio;
}

abstract class Stream : Handle {
        alias FiberedEventList!(void, Stream, ubyte[]) readEventList;
    private:
        bool _isReading;
        
        class readOperationContext : OperationContext!Stream {
            public:
                ubyte[] readData;
                this(Stream target) {
                    super(target);
                }
        }

    public:

        this(Loop loop, uv_handle_type type) {
            super(loop, type);
        }

        ~this() {
            std.stdio.writeln("Destroying stream");
        }
        
        @property uv_stream_t* handle() {
            return cast(uv_stream_t*)super.handle;
        }
        alias Handle.handle handle;

        void write(ubyte[] data) {
            ensureOpen;
            auto wc = new OperationContext!Stream(this);
            duv_write(this.handle, wc, data, function (uv_stream_t * thisHandle, contextObj, status writeStatus) {
                    auto wc = cast(OperationContext!Stream)contextObj;
                    wc.resume(writeStatus);
            });
            scope (exit) delete wc;
            wc.yield;
            wc.completed;
            debug std.stdio.writeln("Write completed");
        }


        ubyte[] read() {
            ensureOpen;
            auto rx = new readOperationContext(this);
            rx.target._isReading = true;
            duv_read_start(this.handle, rx, (uv_stream_t * client_conn, Object readContext, ptrdiff_t nread, ubyte[] data) {
                    auto rx = cast(readOperationContext)readContext;
                    Stream thisStream = rx.target;
                    int status = cast(int)nread;
                    rx.readData = data;
                    new Check().start((check){
                        rx.resume(status);
                        check.stop;
                    });
            });
            scope (exit) delete rx;
            debug std.stdio.writeln("read (activated block) will yield");
            rx.yield;
            debug std.stdio.writeln("read (activated block) continue after yield");
            duv_read_stop(this.handle);
            rx.target._isReading = false;
            try {
                rx.completed;
            } catch(LoopException lex) {
                if(lex.name == "EOF") {
                    debug std.stdio.writeln("EOF detected, forcing close");
                    close(true);
                    throw lex;
                }
            }
            return rx.readData;
        }

        void stopReading() {
            /*if(_readTrigger) {
                debug std.stdio.writeln("stopReading: reseting trigger");
                auto t = _readTrigger;
                _readEvent = null;
                _readTrigger = null;
                t.reset();
            } else {
                debug std.stdio.writeln("(stopReading had no effect");
            }*/
        }

    protected:
        override void closeCleanup(bool async) {
            stopReading();
        }
}
