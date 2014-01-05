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
                lineWrite("Connection: close");
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
                close();
                debug std.stdio.writeln("...Closed");
            }
            debug std.stdio.writeln("...Ended");
        }

        void close() {
            _connection.stop();
        }
}

class HttpConnection {
    alias FiberedEventList!(void, HttpRequest, HttpResponse) processEventList;

    private:
        processEventList _processAction;
        processEventList.Trigger _processTrigger;
        TcpStream _stream;
        HttpParser _parser;

        HttpRequest _currentRequest;
        HttpResponse _currentResponse;
        HttpContext _currentContext;

        void onMessageBegin(HttpParser p) {
            debug std.stdio.writeln("HTTP message began");
            _currentRequest = new HttpRequest;
            _currentResponse = new HttpResponse(this);
            _currentContext = new HttpContext(_currentRequest, _currentResponse);
        }

        void onUrl(HttpParser p, string uri) {
            _currentRequest.rawUri = uri;
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
            _processTrigger(_currentRequest, _currentResponse);
        }

        void _startProcessing() {
            try {
                debug std.stdio.writeln("Reading to Process HTTP Requests");
                _stream.read ^ (stream, data) {
                    //debug std.stdio.writeln("HttpConnection Read: ", cast(string)data);
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
            _stream = null;
        }

        void _stopProcessing() {
            debug std.stdio.writeln("_Stopping connection, closing stream");
            _stream.stopReading();
            //_stream.close();
        }

        void stop() {
            debug std.stdio.writeln("Stopping connection");
           auto t = _processTrigger;
           _processTrigger = null;
           _processAction = null;
           t.reset();
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
            if(_processTrigger is null) {
                _processAction = new processEventList;
                _processTrigger = _processAction.own((trigger, activated) {
                    if(activated) {
                        _startProcessing();
                    } else {
                        _stopProcessing();
                    }
                });
            }
            return _processAction;
        }

        @property Stream stream() {
            return _stream;
        }

}

class HttpListener
{
    alias EventList!(void, HttpConnection) startEventList;
    private:
        TcpStream _server;
        startEventList _startAction;
        startEventList.Trigger _startTrigger;

    public:
        this() {
            _server = new TcpStream;
        }

        TThis bind4(this TThis)(string address, int port) {
            _server.bind4(address, port);
            return cast(TThis)this;
        }

        startEventList start() {
            if(_startTrigger is null) {
                _startAction = new startEventList;
                _startTrigger = _startAction.own((trigger, activated) {
                    if(activated) {
                        _server.listen ^ (newClient) {
                           auto connection = new HttpConnection(newClient);
                           _startTrigger(connection);
                        };
                    }
                });
            }
            return _startAction;
        }
        
}
