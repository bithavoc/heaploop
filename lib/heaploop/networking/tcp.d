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
            uv_tcp_init(this.loop.handle, cast(uv_tcp_t*)this.handle).duv_last_error(this.loop.handle).completed();
        }

    public:

        this() {
            this(Loop.current);
        }

        this(Loop loop) {
            super(loop, uv_handle_type.TCP);
        }

        void bind4(string address, int port) {
            duv_tcp_bind4(cast(uv_tcp_t*)handle, std.string.toStringz(address), port).duv_last_error(this.loop.handle).completed();
        }

        listenEventList listen(int backlog = 100) {
            if(_listenEvent is null) {
                _listenEvent = new listenEventList;
                auto lc = new OperationContext!TcpStream(this);
                _listenTrigger = _listenEvent.own((activated) {
                        if(activated) {
                            duv_listen(this.handle, backlog, lc, function (uv_stream_t * thisHandle, Object contextObj, int status) {
                                auto lc = cast(OperationContext!TcpStream)contextObj;
                                if(status.isError) {
                                    lc.resume(status);
                                } else {
                                    TcpStream thisStream = lc.target;
                                    TcpStream client = new TcpStream(thisStream.loop);
                                    int acceptStatus = uv_accept(thisHandle, cast(uv_stream_t*)client.handle);
                                    if(acceptStatus.isError) {
                                        lc.resume(acceptStatus);
                                    } else {
                                        thisStream._listenTrigger(client);
                                    }
                                }
                            });
                            lc.yield;
                            lc.completed;
                        } else {
                            // TODO: Deactivation, uv_listen_stop?
                        }
                 });
            }
            return _listenEvent;
        }
}

