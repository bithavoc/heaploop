module heaploop.looping;

import events;
import duv.c;
import duv.types;

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
