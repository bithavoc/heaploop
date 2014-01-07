module heaploop.networking.tcp;
import heaploop.streams;
import heaploop.looping;
import duv.c;
import duv.types;
import events;

void heaploop_tcp_stream_listen_cb(uv_stream_t * thisHandle, Object contextObj, int status) {
    TcpStream stream = cast(TcpStream)contextObj;
    if(stream._acceptContext !is null) {
        // resume inmediately
        stream._acceptContext.resume(status);
    } else {
        stream._acceptPending = true;
        if(status.isError) {
            stream._listenError = duv_last_error(status, stream.loop.handle);
        }
        // let go, wait for .accept to accept
    }
}
class TcpStream : Stream
{
    alias FiberedEventList!(void, TcpStream) listenEventList;
    private:
        bool _listening;
        OperationContext!TcpStream _acceptContext;
        duv_error _listenError;
        bool _acceptPending;


    protected:

        override void initializeHandle() {
            uv_tcp_init(this.loop.handle, cast(uv_tcp_t*)this.handle).duv_last_error(this.loop.handle).completed();
            debug std.stdio.writeln("TCP handle initialized");
        }
        TcpStream _acceptNow() {
            TcpStream client = new TcpStream(this.loop);
            int acceptStatus = uv_accept(this.handle, cast(uv_stream_t*)client.handle);
            if(acceptStatus.isError) {
                acceptStatus.duv_last_error(this.loop.handle).completed;
            }
            return client;
        }

    public:

        this() {
            this(Loop.current);
        }

        this(Loop loop) {
            super(loop, uv_handle_type.TCP);
        }
        ~this() {
            std.stdio.writeln("Destroying TCP stream");
        }

        void bind4(string address, int port) {
            duv_tcp_bind4(cast(uv_tcp_t*)handle, std.string.toStringz(address), port).duv_last_error(this.loop.handle).completed();
        }

        @property bool isListening() {
            return _listening;
        }

        void listen(int backlog) {
            if(_listening) {
                throw new Exception("Stream already listening");
            }
            duv_listen(this.handle, backlog, this, &heaploop_tcp_stream_listen_cb).duv_last_error(this.loop.handle).completed();
            _listening = true;
        }

        TcpStream accept() {
            if(_acceptPending) {
                if(_listenError.hasError) {
                    auto err = _listenError;
                    _listenError = _listenError.init;
                    err.completed;
                }
                return _acceptNow();
            }
            _acceptContext  = new OperationContext!TcpStream(this);
            _acceptContext.yield;
            _acceptContext.completed;
            _acceptContext = null;
            delete _acceptContext;
            return _acceptNow();
        }
/*
        listenEventList listen(int backlog = 100) {
            if(_listenEvent is null) {
                _listenEvent = new listenEventList;
                auto lc = new OperationContext!TcpStream(this);
                _listenTrigger = _listenEvent.own((trigger, activated) {
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
        */
}

