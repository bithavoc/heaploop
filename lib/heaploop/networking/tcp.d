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
        bool _connecting;

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

        @property uv_tcp_t* handle() {
            return cast(uv_tcp_t*)super.handle;
        }
        alias Stream.handle handle;

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
                duv_listen(cast(uv_stream_t*)this.handle, backlog, cx, function (uv_stream_t* thisHandle, Object contextObj, int status) {
                    auto cx = cast(acceptOperationContext)contextObj;
                    cx.update(status);
                    if(status.isError) {
                        cx.target.close();
                        cx.resume();
                        return;
                    } else {
                        TcpStream client = new TcpStream(cx.target.loop);
                        int acceptStatus = uv_accept(cast(uv_stream_t*)cx.target.handle, cast(uv_stream_t*)client.handle);
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

        @property bool isConnecting() {
            return _connecting;
        }

        void connect4(string address, int port) {
            if(_connecting) {
                throw new Exception("Stream already connecting");
            }
            _connecting = true;
            scope cx = new OperationContext!TcpStream(this);
            duv_tcp_connect4(this.handle, cx, address, port, function (uv_tcp_t* thisHandle, Object contextObj, int status) {
                auto cx = cast(OperationContext!TcpStream)contextObj;
                cx.update(status);
                debug std.stdio.writeln("connect status", status);
                if(status.isError) {
                    cx.target.close();
                }
                cx.resume();
            }).duv_last_error(this.loop.handle).completed();
            cx.yield;
            cx.completed;
        }
}

