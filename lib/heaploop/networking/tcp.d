module heaploop.networking.tcp;
import heaploop.streams;
import heaploop.looping;
import duv.c;
import duv.types;
import events;

class TcpStream : Stream
{
    private:
        bool _listening;

    protected:

        override void initializeHandle() {
            uv_tcp_init(this.loop.handle, cast(uv_tcp_t*)this.handle).duv_last_error(this.loop.handle).completed();
            debug std.stdio.writeln("TCP handle initialized");
        }

        class acceptOperationContext : OperationContext!TcpStream {
            public:
                TcpStream client;
                this(TcpStream target) {
                    super(target);
                }
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

        @property bool isListening() {
            return _listening;
        }

        Action!(void, TcpStream) listen(int backlog) {
            if(_listening) {
                throw new Exception("Stream already listening");
            }
            return new Action!(void, TcpStream)((trigger) {
                _listening = true;
                auto cx = new acceptOperationContext(this);
                duv_listen(this.handle, backlog, cx, function (uv_stream_t* thisHandle, Object contextObj, int status) {
                    auto cx = cast(acceptOperationContext)contextObj;
                    cx.update(status);
                    if(status.isError) {
                        cx.target.close();
                        cx.resume();
                        return;
                    } else {
                        TcpStream client = new TcpStream(cx.target.loop);
                        int acceptStatus = uv_accept(cx.target.handle, cast(uv_stream_t*)client.handle);
                        if(acceptStatus.isError) {
                            cx.target.close();
                            delete client;
                        } else {
                            cx.client = client;
                        }
                        cx.resume();
                        return;
                    }
                }).duv_last_error(this.loop.handle).completed();
                while(true) {
                    cx.yield;
                    cx.completed;
                    trigger(cx.client);
                }
            });
        }
}

