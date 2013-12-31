module heaploop.networking.tcp;
import heaploop.streams;
import heaploop.looping;
import duv.c;
import duv.types;
import events;

class TcpStream : Stream
{
    alias FiberedEventList!(void, TcpStream) listenEventList;
    private:
        listenEventList _listenEvent;
        listenEventList.Trigger _listenTrigger;
    protected:

        override void init() {
            uv_tcp_init(this.loop.handle, cast(uv_tcp_t*)this.handle).check();
        }

    public:

        this() {
            this(Loop.current);
        }

        this(Loop loop) {
            super(loop, uv_handle_type.TCP);
        }

        void bind4(string address, int port) {
            duv_tcp_bind4(cast(uv_tcp_t*)handle, std.string.toStringz(address), port).check();
        }

        listenEventList listen(int backlog = 100) {
            if(_listenEvent is null) {
                _listenEvent = new listenEventList;
                _listenTrigger = _listenEvent.own((activated) {
                        duv_listen(this.handle, backlog, this, function (uv_stream_t * thisHandle, Object contextObj, status st) {
                            st.check();
                            TcpStream thisStream = cast(TcpStream)contextObj;

                            TcpStream client = new TcpStream(thisStream.loop);
                            uv_accept(thisHandle, cast(uv_stream_t*)client.handle).check();
                            thisStream._listenTrigger(client);
                        });
                 });
            }
            return _listenEvent;
        }
}

