module heaploop.looping;

import events;
import duv.c;
import duv.types;
import core.thread;

enum RunMode {
  Default = 0,
  Once,
  NoWait
};

class Loop {
    private:
        uv_loop_t * _loopPtr;
        bool _custom;
        static Loop _current;
    public:

        this(uv_loop_t * ptr, bool custom) {
            _loopPtr = ptr;
            _custom = custom;
        }

        @property bool isCustom() {
            return _custom;
        }

        @property static Loop current() {
            if(_current is null) {
                _current = new Loop(uv_default_loop, false);
            }
            return _current;
        }
        void run(RunMode mode) {
            uv_run(_loopPtr, cast(uv_run_mode)mode);
        }
        @property uv_loop_t* handle() {
            return _loopPtr;
        }
}

Action!void loop(RunMode mode = RunMode.Default) {
    return new Action!void((trigger) {
            trigger();
            Loop.current.run(RunMode.Default);
    });
}

interface Looper {
    @property Loop loop();
}

class OperationContext(T:Looper) {
    private:
        Fiber _fiber;
        T _target;
    public:
        this(T target) {
            _fiber = Fiber.getThis;
            _target = target;
            debug std.stdio.writeln("new OperationContext");
        }
        ~this() {
            debug std.stdio.writeln("OperationContext destroyed");
        }
    int status;
    duv_error error;
    bool finish;

    void update(int status) {
        this.status = status;
        error = duv_last_error(this.status, target.loop.handle);
    }

    void resume() {
        debug std.stdio.writeln("Trying to resume while the fiber is in state ", _fiber.state);
        if(_fiber.state != Fiber.State.HOLD) {
            return;
        }
        _fiber.call;
    }

    @property bool hasError() pure nothrow {
        return error.isError;
    }

    @property Fiber fiber() nothrow {
        return _fiber;
    }

    @property target() nothrow {
        return _target;
    }

    void yield() {
        fiber.yield;
    }

    void completed() {
        error.completed;
    }
}

@property bool isError(int status) pure nothrow {
    return status < 0;
}

@property bool isError(duv_error error) pure nothrow {
    return error.name !is null;
}

void completed(duv_error error, string file = __FILE__, size_t line = __LINE__) {
    if(error.isError) {
        throw new LoopException(error.message, error.name, file, line);
    }
}

class LoopException : Exception
{
    private:
        string _name;

    public:
        this(string msg, string name, string file = __FILE__, size_t line = __LINE__, Throwable next = null) {
            super(msg, file, line, next);
            _name = name;
        }

        @property string name() pure nothrow {
            return _name;
        }

        override string toString() {
            return std.string.format("%s: %s", this.name, this.msg);
        }

}

alias void delegate(Check sender) CheckDelegate;
class Check : Handle {
    private:
        CheckDelegate _delegate;
        bool _started;
    protected:
        override void initializeHandle() {
            uv_check_init(loop.handle, this.handle);
        }
    public:
        this(Loop loop = Loop.current) {
            super(loop, uv_handle_type.CHECK);
        }

        void start(CheckDelegate del) {
            stop();
            _started = true;
            _delegate = del;
            duv_check_start(this.handle, this, (h, c, s) {
               Check self = cast(Check)c; 
               self._delegate(self);
            });
        }

        void stop() {
            if(!_started) return;
            _delegate = null;
            duv_check_stop(handle);
            _started = false;
        }

        @property {

            uv_check_t* handle() {
                return cast(uv_check_t*)super.handle;
            }

            bool started() {
                return _started;
            }

        }

        alias Handle.handle handle;


        ~this() {
            stop();
        }

        static Check once(void delegate(Check check) del, Loop loop = Loop.current) {
            auto check = new Check(loop);
            check.start((c) {
                    scope (exit) c.stop;
                    scope (exit) c.close;
                    del(c);
            });
            return check;
        }
}

abstract class Handle : Looper {
    private:
        void * _handle;
        Loop _loop;
        bool _isOpen;

    protected:

        abstract void initializeHandle();
        
        void closeCleanup(bool async) {

        }

        void ensureOpen(string callerName = __FUNCTION__) {
            if(!isOpen) {
                throw new LoopException(std.string.format("%s requires the handle to be open", callerName), "CLOSED_HANDLE");
            }
        }


    public:

        this(Loop loop, uv_handle_type type) {
            _loop = loop;
            _handle = duv__handle_alloc(type);
            _isOpen = true;
            this.initializeHandle();
            debug std.stdio.writeln("(Handle just initialized OPEN handle ", _handle, ")");
        }

        ~this() {
            debug std.stdio.writeln("Destroying handle");
            close(); // close the handle without waiting
        }

        @property {
            Loop loop() pure nothrow {
                return _loop;
            }
            bool isOpen() {
                if(_isOpen) {
                    return !duv_is_closing(this.handle);
                }
                return _isOpen;
            }
            uv_handle_t* handle() pure nothrow {
                return cast(uv_handle_t*)_handle;
            }
        }
        void close(bool async=true) {
            if(!isOpen) {
                debug std.stdio.writeln("(tried to close but handle ", _handle, " was reported to be closed or closing already)");
                return;
            }
            _isOpen = false;
            debug std.stdio.writeln("(about to CLOSE handle ", _handle, ") of type ", this);
            closeCleanup(true);
            debug std.stdio.writeln("closing handle async");

            duv_handle_close_async(this.handle);
            debug std.stdio.writeln("closed handle async");
            _loop = null;
        }

}
