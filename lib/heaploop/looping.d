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

FiberedEventList!void loop(RunMode mode = RunMode.Default) {
    auto action = new FiberedEventList!void;
    action.Trigger trigger;
    trigger = action.own((trigger, activated) {
        if(activated) {
            trigger();
            Loop.current.run(RunMode.Default);
        }
    });
    return action;
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
        }
    int status;
    duv_error error;
    bool finish;

    void resume(int status = 0) {
        debug std.stdio.writeln("Trying to resume while the fiber is in state ", _fiber.state);
        if(_fiber.state != Fiber.State.HOLD) {
            return;
        }
        error = duv_last_error(status, target.loop.handle);
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

void completed(duv_error error) {
    if(error.isError) {
        throw new LoopException(error.message, error.name);
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

alias void delegate() CheckDelegate;
class Check {
    private:
        CheckDelegate _delegate;
        uv_check_t * _handle;
        bool _started;
        Loop _loop;
    public:
        this(Loop loop = Loop.current) {
            _loop = loop;
            _handle = uv_handle_alloc!(uv_handle_type.CHECK); 
            uv_check_init(_loop.handle, _handle).duv_last_error(_loop.handle).completed;
        }

        void start(CheckDelegate del) {
            stop();
            _delegate = del;
            duv_check_start(_handle, this, (h, c, s) {
               Check self = cast(Check)c; 
               self._delegate();
            });
        }

        void stop() {
            if(!_started) return;
            duv_check_stop(_handle);
        }

        @property bool started() {
            return _started;
        }

        @property uv_check_t * handle() {
            return _handle;
        }

        ~this() {
            stop();
        }
}
