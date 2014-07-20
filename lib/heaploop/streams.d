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
                    wc.update(writeStatus);
                    if(writeStatus.isError) {
                        // we must close inmediately we receive the error and before continue in the fiber
                        wc.target.close();
                    }
                    wc.resume();
            });
            scope (exit) delete wc;
            wc.yield;
            wc.completed;
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
                        int status = cast(int)nread;
                        auto rx = cast(readOperationContext)readContext;
                        rx.update(status);
                        Stream thisStream = rx.target;
                        rx.readData = data;
                        if(status.isError) {
                            // we must close inmediately we receive the error and before continue in the fiber
                            rx.target.close();
                        }
                        rx.resume();
                });
                scope (exit) stopReading();
                while(!rx.stopped) {
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
                                debug std.stdio.writeln("read detected, forcing close");
                                close();
                                throw lex;
                            }
                        }
                        trigger(rx.readData);
                    } else {
                        debug std.stdio.writeln("read was stopped, breaking read loop");
                        break;
                    }
                }
                _readOperation = null;
            });
        }

        ubyte[] readOnce() {
            ensureOpen;
            if(_isReading) {
                throw new Exception("Stream is already reading");
            }
            _isReading = true;
            auto rx = _readOperation = new readOperationContext(this);
            duv_read_start(this.handle, rx, (uv_stream_t * client_conn, Object readContext, ptrdiff_t nread, ubyte[] data) {
                    int status = cast(int)nread;
                    auto rx = cast(readOperationContext)readContext;
                    rx.update(status);
                    Stream thisStream = rx.target;
                    rx.readData = data;
                    if(status.isError) {
                        // we must close inmediately we receive the error and before continue in the fiber
                        rx.target.close();
                    }
                    rx.resume();
            });
            scope (exit) stopReading();
            debug std.stdio.writeln("read (activated block) will yield");
            rx.yield;
            debug std.stdio.writeln("read (activated block) continue after yield");
            try {
                rx.completed;
            } catch(LoopException lex) {
                if(lex.name == "EOF") {
                    debug std.stdio.writeln("EOF detected, forcing close");
                    close();
                } else {
                    debug std.stdio.writeln("error detected, forcing close");
                    close();
                    throw lex;
                }
            }
            return rx.readData;
        }

        void stopReading() {
            // [WARNING] might be executed from fiber or thread
            if(_isReading) {
                debug std.stdio.writeln("stopReading");
                duv_read_stop(this.handle);
                _isReading = false;
                if(_readOperation) {
                    _readOperation.stopped = true;
                    _readOperation.resume;
                    _readOperation = null;
                }
            }
        }

    protected:
        override void closeCleanup(bool async) {
            stopReading();
        }
}
