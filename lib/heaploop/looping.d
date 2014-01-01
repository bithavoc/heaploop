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
    trigger = action.own((activated) {
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

    void resume(int status = 0) {
        error = duv_last_error(status, target.loop.handle);
        fiber.call;
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
        throw new Exception(std.string.format("%s: %s", error.name, error.message));
    }
}
