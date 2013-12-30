module heaploop.streams;
import heaploop.looping;
import duv.c;
import duv.types;

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

    protected:

        abstract void init();


}
