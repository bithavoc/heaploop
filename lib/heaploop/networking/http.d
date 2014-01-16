module heaploop.networking.http;
import heaploop.networking.tcp;
import heaploop.looping;
import heaploop.streams;
import events;
import std.string : format;
import http.parser.core;

class HttpContext {
private:
    HttpRequest _request;
    HttpResponse _response;

    this(HttpRequest request, HttpResponse response) {
        _request = request;
        _response = response;
        _request.context = this;
        _response.context = this;
    }

    public:
    @property {
        HttpRequest request() {
            return _request;
        }
        HttpResponse response() {
            return _response;
        }
    }
}

class HttpRequest {
    private:
        string _rawUri;
        Uri _uri;
        string _method;
        HttpHeader[] _headers;
        HttpContext _context;
        HttpVersion _protocolVersion;

    public:
        this() {
        }

        @property {
            string rawUri() {
                return _rawUri;
            }
            void rawUri(string uri) {
                _rawUri = uri;
            }
        }

        @property {
            Uri uri() {
                return _uri;
            }
            void uri(Uri uri) {
                _uri = uri;
            }
        }

        @property {
            string method() {
                return _method;
            }
            void method(string m) {
                _method = m;
            }
        }
        @property {
            HttpHeader[] headers() {
                return _headers;
            }
        }

        void addHeader(HttpHeader header) {
            _headers ~= header;
        }

        @property {
            HttpContext context() {
                return _context;
            }
            package void context(HttpContext context) {
                _context = context;
            }
            HttpVersion protocolVersion() {
                return _protocolVersion;
            }
            void protocolVersion(HttpVersion v) {
                _protocolVersion = v;
            }
        }
}

class HttpResponse {
    private:
        HttpConnection _connection;
        bool _headersSent;
        uint _statusCode;
        string _statusText;
        string _contentType;
        HttpContext _context;
        bool _chunked;
        ubyte[] _bufferedWrites;

        void lineWrite(string data = "") {
            _connection.stream.write(cast(ubyte[])(data ~ "\r\n"));
        }

        void _ensureHeadersSent() {
            if(!headersSent) {
                auto stream = _connection.stream;
                lineWrite("HTTP/%s %d %s".format(_context.request.protocolVersion.toString, _statusCode, _statusText));
                lineWrite("Content-Type: %s; charset=UTF-8".format(_contentType));
                if(_chunked) {
                    lineWrite("Transfer-Encoding: chunked");
                } else {
                    lineWrite("Content-Length: %d".format(_bufferedWrites.length));
                }
                //lineWrite("Connection: close");
                lineWrite();
                _headersSent = true;
            }
        }

    package:
        void _init() {
            auto ver = _context.request.protocolVersion;
            bool is1_0 = ver.major == 1 && ver.minor == 0;
            _chunked = !is1_0;
        }

    public:
        this(HttpConnection connection) {
            _connection = connection;
            this.statusCode = 200;
            this.contentType = "text/plain";
        }

        @property bool headersSent() {
            return _headersSent;
        }

        @property {
            uint statusCode() {
                return _statusCode;
            }
            void statusCode(uint statusCode) {
                _statusCode = statusCode;
                switch(statusCode) {
                    case 200:
                        _statusText = "OK";
                        break;
                    default:
                        throw new Exception(std.string.format("Unknown HTTP status code %s... pull request time?", _statusCode));
                }
            }
        }

        @property {
            string contentType() {
                return _contentType;
            }

            void contentType(string contentType) {
                _contentType = contentType;
            }
        }

        @property {
            HttpContext context() {
                return _context;
            }
            package void context(HttpContext context) {
                _context = context;
            }
        }

        void write(ubyte[] data) {
            if(_chunked) {
                _ensureHeadersSent();
                _connection.stream.write((cast(ubyte[])format("%x\r\n", data.length)));
                _connection.stream.write(data ~ cast(ubyte[])"\r\n");
            } else {
                _bufferedWrites ~= data;
            }
        }

        void write(string data) {
            write(cast(ubyte[])data);
        }

        void end() {
            debug std.stdio.writeln("Ending");
            _ensureHeadersSent();
            if(_chunked) {
                write(cast(ubyte[])[]);
            } else {
                _connection.stream.write(_bufferedWrites);
                debug std.stdio.writeln("Closing");
                //close();
                debug std.stdio.writeln("...Closed");
            }
            debug std.stdio.writeln("...Ended");
        }

        void close() {
            _connection.stop();
        }
}

class HttpConnection {
    alias Action!(void, HttpRequest, HttpResponse) processEventList;

    private:
        processEventList _processAction;
        TcpStream _stream;
        HttpParser _parser;

        HttpRequest _currentRequest;
        HttpResponse _currentResponse;
        HttpContext _currentContext;
        void delegate(HttpRequest, HttpResponse) _processCallback;

        void onMessageBegin(HttpParser p) {
            debug std.stdio.writeln("HTTP message began");
            _currentRequest = new HttpRequest;
            _currentResponse = new HttpResponse(this);
            _currentContext = new HttpContext(_currentRequest, _currentResponse);
        }

        void onUrl(HttpParser p, string uri) {
            _currentRequest.rawUri = uri;
            _currentRequest.uri = Uri(_currentRequest.rawUri);
        }

        void onStatus(HttpParser p, string status) {
        }

        void onHeadersComplete(HttpParser p) {
            _currentRequest.method = p.method;
            _currentRequest.protocolVersion = p.protocolVersion;
            _currentResponse._init();
        }

        void onHeader(HttpParser p, HttpHeader header) {
            _currentRequest.addHeader(header);
        }

        void onMessageComplete(HttpParser p) {
            debug std.stdio.writeln("protocol version set, ", p.protocolVersion.toString);
            _processCallback(_currentRequest, _currentResponse);
        }

        void _startProcessing(void delegate(HttpRequest, HttpResponse) callback) {
            _processCallback = callback;
            try {
                debug std.stdio.writeln("Reading to Process HTTP Requests");
                stream.read ^ (data) {
                    _parser.execute(data);
                };
            } catch(LoopException lex) {
                if(lex.name == "EOF")  {
                    debug std.stdio.writeln("Connection closed");
                } else {
                    throw lex;
                }
            }
            debug std.stdio.writeln("Stopped processing requests");
            _stopProcessing();
        }

        void _stopProcessing() {
            if(_stream is null) return;
            debug std.stdio.writeln("_Stopping connection, closing stream");
            _stream.stopReading();
            _stream.close();
            _stream = null;
            _parser = null;
            _currentRequest = null;
            _currentResponse = null;
            _currentContext = null;
            debug std.stdio.writeln("_Stopping connection, OK");
        }
        ~this() {
           debug std.stdio.writeln("Collecting HttpConnection");
        }

    public:
        this(TcpStream stream) {
            _stream = stream;
            _parser = new HttpParser(HttpParserType.REQUEST);
            _parser.onMessageBegin = &onMessageBegin;
            _parser.onHeader = &onHeader;
            _parser.onHeadersComplete = &onHeadersComplete;
            _parser.onMessageComplete = &onMessageComplete;
            _parser.onUrl = &onUrl;
        }

        processEventList process() {
            if(_processAction is null) {
                _processAction = new processEventList((trigger) {
                    _startProcessing(trigger);
                });;
            }
            return _processAction;
        }

        @property Stream stream() {
            return _stream;
        }

        void stop() {
           debug std.stdio.writeln("Stopping connection");
           _stopProcessing;
        }
}

class HttpListener
{
    private:
        TcpStream _server;

    public:
        this() {
            _server = new TcpStream;
        }

        TThis bind4(this TThis)(string address, int port) {
            _server.bind4(address, port);
            return cast(TThis)this;
        }

        Action!(void, HttpConnection) listen(int backlog = 50000) {
            return new Action!(void, HttpConnection)((trigger) {
                _server.listen(backlog) ^ (client) {
                    auto connection = new HttpConnection(client);
                    trigger(connection);
                };
            });
        }
}
