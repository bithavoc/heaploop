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
    private:
        bool _isReading;
        readOperationContext _readOperation;
        
        class readOperationContext : OperationContext!Stream {
            public:
                ubyte[] readData;
                bool stopped;
                this(Stream target) {
                    super(target);
                }
        }

    public:

        this(Loop loop, uv_handle_type type) {
            super(loop, type);
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
            try {
                wc.completed;
            } catch(Exception ex) {
                close();
                throw ex;
            }
            debug std.stdio.writeln("Write completed");
        }

        @property bool isReading() pure nothrow {
            return _isReading;
        }

        Action!(void, ubyte[]) read() {
            ensureOpen;
            return new Action!(void, ubyte[])((trigger) {
                _isReading = true;
                auto rx = _readOperation = new readOperationContext(this);
                duv_read_start(this.handle, rx, (uv_stream_t * client_conn, Object readContext, ptrdiff_t nread, ubyte[] data) {
                        auto rx = cast(readOperationContext)readContext;
                        Stream thisStream = rx.target;
                        int status = cast(int)nread;
                        rx.readData = data;
                        Check.once((check){
                            rx.resume(status);
                        });
                });
                scope (exit) stopReading();
                while(true) {
                    debug std.stdio.writeln("read (activated block) will yield");
                    rx.yield;
                    debug std.stdio.writeln("read (activated block) continue after yield");
                    if(!rx.stopped) {
                        try {
                            rx.completed;
                        } catch(LoopException lex) {
                            if(lex.name == "EOF") {
                                debug std.stdio.writeln("EOF detected, forcing close");
                                close();
                                break;
                            } else {
                                throw lex;
                            }
                        }
                        trigger(rx.readData);
                    } else {
                        debug std.stdio.writeln("read was stopped, breaking read loop");
                        break;
                    }
                }
            });
        }

        void stopReading() {
            if(_isReading) {
                debug std.stdio.writeln("stopReading");
                duv_read_stop(this.handle);
                _isReading = false;
                if(_readOperation !is null) {
                    _readOperation.stopped = true;
                    _readOperation.resume;
                }
                _readOperation = null;
            }
        }

    protected:
        override void closeCleanup(bool async) {
            stopReading();
        }
}
