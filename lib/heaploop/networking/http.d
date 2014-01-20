module heaploop.networking.http;
import heaploop.networking.tcp;
import heaploop.looping;
import heaploop.streams;
import events;
import std.string : format;
import http.parser.core;
debug {
    import std.stdio : writeln;
}

/*
 * HTTP Common
 */

abstract class HttpConnectionBase(TIncomingMessage : HttpIncomingMessage) : Looper {
    private:
        TcpStream _stream;
        HttpParser _parser;

        TIncomingMessage _currentMessage;

        void _onMessageBegin(HttpParser p) {
            debug std.stdio.writeln("HTTP message began");
            _currentMessage = createIncomingMessage();
            onMessageBegin();
        }

        void onUrl(HttpParser p, string uri) {
            _currentMessage.rawUri = uri;
            _currentMessage.uri = Uri(_currentMessage.rawUri);
        }

        void onHeadersComplete(HttpParser p) {
            _currentMessage.protocolVersion = p.protocolVersion;
            debug std.stdio.writeln("protocol version set, ", p.protocolVersion.toString);
            onBeforeProcess();
            onProcessMessage();
        }

        void onBody(HttpParser parser, HttpBodyChunk chunk) {
            debug writeln("HTTP Response Message: read some BODY data: ", chunk.buffer);
            auto cx = _currentMessage._ensureReadOperation();
            cx.buffer(chunk);
            cx.resume;
        }

        void onHeader(HttpParser p, HttpHeader header) {
            _currentMessage.addHeader(header);
        }

        void onMessageComplete(HttpParser p) {
            debug std.stdio.writeln("protocol version set, ", p.protocolVersion.toString);
        }

        void _stopProcessing() {
            if(_stream is null) return;
            debug std.stdio.writeln("_Stopping connection, closing stream");
            _stream.stopReading();
            _stream.close();
            _stream = null;
            _parser = null;
            debug std.stdio.writeln("_Stopping connection, OK");
        }
        ~this() {
           debug std.stdio.writeln("Collecting HttpConnection");
        }

package:
        void write(ubyte[] data) {
            // TODO: make sure we are not in read mode
            _stream.write(data);
        }

    protected:
        @property {
            TIncomingMessage currentMessage() nothrow pure {
                return _currentMessage;
            }

            HttpParser parser() nothrow pure {
                return _parser;
            }
        }

        abstract TIncomingMessage createIncomingMessage();

        abstract void onMessageBegin();

        abstract void onBeforeProcess();
        
        abstract void onProcessMessage();

        void startProcessing() {
            try {
                debug std.stdio.writeln("Reading to Process HTTP Requests");
                _stream.read ^ (data) {
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

    public:
        this(TcpStream stream, HttpParserType parserType) {
            _stream = stream;
            _parser = new HttpParser(parserType);
            _parser.onMessageBegin = &_onMessageBegin;
            _parser.onHeader = &onHeader;
            _parser.onHeadersComplete = &onHeadersComplete;
            _parser.onMessageComplete = &onMessageComplete;
            _parser.onUrl = &onUrl;
            _parser.onBody = &onBody;
        }


        void stop() {
           debug std.stdio.writeln("Stopping connection");
           _stopProcessing;
        }

        @property {
            Loop loop() nothrow pure {
                return _stream.loop;
            }
        }
}

abstract class HttpMessage : Looper {
    private:
        Loop _loop;
        HttpHeader[] _headers;
        HttpVersion _version;

    package:
        this(Loop loop) 
            in {
                assert(loop !is null, "loop is required to create HttpMessage");
            }
            body {
                _loop = loop;
            }
    public:

        @property {
            Loop loop() nothrow pure {
                return _loop;
            }

            HttpHeader[] headers() nothrow pure {
                return _headers;
            }
        }

        void addHeader(HttpHeader header) {
            _headers ~= header;
        }

        void protocolVersion(in HttpVersion v) {
            _version = v;
        }

        HttpVersion protocolVersion() {
            return _version;
        }
}

abstract class HttpIncomingMessage : HttpMessage
{
    private:
        string _rawUri;
        Uri _uri;
        readOperation _readOperation;
        HttpConnectionBase!HttpIncomingMessage connection;
    package:

        class readOperation : OperationContext!HttpIncomingMessage {
            public:
               HttpBodyChunk bufferedChunk;
               bool stopped;
               this(HttpIncomingMessage target) {
                   super(target);
               }
               @property bool hasBufferedChunk() {
                   return bufferedChunk.buffer.length > 0;
               }
               HttpBodyChunk consumeBufferedChunk() {
                   scope (exit) {
                       bufferedChunk = HttpBodyChunk.init;
                   }
                   return bufferedChunk;
               }
               void buffer(HttpBodyChunk chunk) {
                   this.bufferedChunk = HttpBodyChunk(bufferedChunk.buffer ~ chunk.buffer, chunk.isFinal);
                   this.stopped = this.bufferedChunk.isFinal;
               }
        }

        readOperation _ensureReadOperation() {
            if(_readOperation is null) {
                return _readOperation = new readOperation(this);
            }
            return _readOperation;
        }


    public:
        this(HttpConnection connection)
            in {
                assert(connection !is null);
            }
            body {
                super(connection.loop);
            }

            Action!(void, HttpBodyChunk) read() {
                return new Action!(void, HttpBodyChunk)((a) {
                   auto cx = _ensureReadOperation();
                   do {
                       if(cx.hasBufferedChunk) {
                            debug writeln("HTTP Response Message: delivering buffered data");
                            a(cx.consumeBufferedChunk());
                       }
                       if(cx.stopped) {
                            break;
                       }
                       cx.yield;
                       cx.completed;
                   } while(cx.hasBufferedChunk);
                });
            }
        @property {

            string rawUri() {
                return _rawUri;
            }

            void rawUri(string uri) {
                _rawUri = uri;
            }

            Uri uri() {
                return _uri;
            }

            void uri(Uri uri) {
                _uri = uri;
            }
        }
}

/*
 * HTTP Server
 */

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

class HttpRequest : HttpIncomingMessage {
    private:
        string _method;
        HttpContext _context;

    public:

        this(HttpConnection connection) {
            super(connection);
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
            HttpContext context() {
                return _context;
            }
            package void context(HttpContext context) {
                _context = context;
            }
        }
}

class HttpResponse {
    private:
        HttpConnection _connection;
        HttpHeader[] _headers;
        bool _headersSent;
        uint _statusCode;
        string _statusText;
        string _contentType;
        HttpContext _context;
        bool _chunked;
        ubyte[] _bufferedWrites;

        void lineWrite(string data = "") {
            _connection.write(cast(ubyte[])(data ~ "\r\n"));
        }

        void _ensureHeadersSent() {
            if(!headersSent) {
                lineWrite("HTTP/%s %d %s".format(_context.request.protocolVersion.toString, _statusCode, _statusText));
                foreach(header; _headers) {
                    lineWrite(header.name ~ " : " ~ header.value);
                }
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
                _connection.write((cast(ubyte[])format("%x\r\n", data.length)));
                _connection.write(data ~ cast(ubyte[])"\r\n");
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
                _connection.write(_bufferedWrites);
                debug std.stdio.writeln("Closing");
                //close();
                debug std.stdio.writeln("...Closed");
            }
            debug std.stdio.writeln("...Ended");
        }

        void close() {
            _connection.stop();
        }

        void addHeader(string name, string value) {
            addHeader(HttpHeader(name, value));
        }

        void addHeader(HttpHeader header) {
            if(_headersSent) {
                throw new Exception("HTTP headers already sent. HttpResponse.addHeader can not be used after HttpResponse.end");
            }
            _headers ~= header;
        }
}

class HttpConnection : HttpConnectionBase!HttpRequest {
    alias Action!(void, HttpRequest, HttpResponse) processEventList;


    private:
        HttpResponse _currentResponse;
        HttpContext _currentContext;
        void delegate(HttpRequest, HttpResponse) _processCallback;
        processEventList _processAction;
    
    protected:
         override HttpRequest createIncomingMessage() {
             return new HttpRequest(this);
         }

         override void onMessageBegin() {
            _currentResponse = new HttpResponse(this);
            _currentContext = new HttpContext(this.currentMessage, _currentResponse);
         }

         override void onBeforeProcess() {
            _currentMessage.method = this.parser.method;
            _currentResponse._init();
         }
        
         override void onProcessMessage() {
            _processCallback(currentMessage, _currentResponse);
         }
    
    public:
        this(TcpStream stream) {
            _stream = stream;
            super(stream, HttpParserType.REQUEST);
        }
        
        processEventList process() {
            if(_processAction is null) {
                _processAction = new processEventList((trigger) {
                    _processCallback = trigger;
                    startProcessing();
                });
            }
            return _processAction;
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

/*
 * HTTP Client
 */

ushort inferPortForUriSchema(string schema) {
    switch(schema) {
        case "http": return 80;
        default: assert(0, "Unable to infer port number for schema %s".format(schema));
    }
}

class HttpRequestMessage
{
    private:
        string _method;
        HttpVersion _version;
        Uri _uri;

    public:
        @property {

            void method(in string m) {
                _method = m;
            }

            string method() {
                return _method;
            }

            void protocolVersion(in HttpVersion v) {
                _version = v;
            }

            HttpVersion protocolVersion() {
                return _version;
            }

            Uri uri() {
                return _uri;
            }

            void uri(Uri uri) {
                _uri = uri;
            }

        }

        void send(TcpStream stream) {
            string path = null;
            if(_uri.query !is null) {
                path = "%s?%s".format(_uri.path, _uri.query);
            } else {
                path = _uri.path;
            }
            auto writeHeader = delegate void(string s) {
                stream.write(cast(ubyte[])(s ~ "\r\n"));
            };
            writeHeader("%s %s HTTP/%s".format(_method, path, _version.toString));
            writeHeader("Host: %s".format(_uri.host));
            writeHeader("");
            debug writeln("headers send");
        }
}

class HttpResponseMessage : Looper
{
    private:
        TcpStream _stream;
        HttpParser _parser;
        HttpHeader[] _headers;

        class readOperation : OperationContext!HttpResponseMessage {
            public:
               ubyte[] bufferedData;
               bool stopped;
               this(HttpResponseMessage target) {
                   super(target);
               }
               @property bool hasBufferedData() {
                   return bufferedData.length > 0;
               }
               ubyte[] consumeBufferedData() {
                   scope (exit) {
                       bufferedData = null;
                   }
                   return bufferedData;
               }
        }
        readOperation _readOperation;

        readOperation _ensureReadOperation() {
            if(_readOperation is null) {
                return _readOperation = new readOperation(this);
            }
            return _readOperation;
        }

        void onHeader(HttpParser parser, HttpHeader header) {
            _headers ~= header;
        }

        void onHeadersComplete(HttpParser parser) {
            debug writeln("Client headers complete, stop reading");
           _stream.stopReading();
        }
        
        void onMessageComplete(HttpParser parser) {
            
        }

        void onBody(HttpParser parser, HttpBodyChunk chunk) {
            debug writeln("HTTP Response Message: read some data: ", chunk.buffer);
            auto cx = _ensureReadOperation();
            cx.bufferedData ~= chunk.buffer;
            cx.stopped = chunk.isFinal;
            cx.resume;
        }

        void readHeaders() {
            debug writeln("HTTP Response Message: before readHeaders");
           _stream.read ^ (data) {
               _parser.execute(data);
           }; 
            debug writeln("HTTP Response Message: after readHeaders");
        }

    public:
        this(TcpStream stream)
            in {
                assert(stream !is null);
            }
            body {
                _parser = new HttpParser(HttpParserType.RESPONSE);
                _parser.onHeader = &onHeader;
                _parser.onHeadersComplete = &onHeadersComplete;
                _parser.onMessageComplete = &onMessageComplete;
                _parser.onBody = &onBody;
                //_parser.onUrl = &onUrl;
                _stream = stream;
                readHeaders();
            }

            Action!(void, ubyte[]) read() {
                return new Action!(void, ubyte[])((a) {
                   auto cx = _ensureReadOperation();
                   if(cx.hasBufferedData) {
                        debug writeln("HTTP Response Message: delivering buffered data");
                        a(cx.consumeBufferedData());
                   }
                   if(!cx.stopped) {
                       debug writeln("HTTP Response Message: processing more of the body");
                       _stream.read ^ (data) {
                            _parser.execute(data);
                       }; 
                       debug writeln("HTTP Response Message: continue after response read");
                       _readOperation = null;
                   } else {
                       debug writeln("HTTP Response Message: body was entirely buffered");
                   }
                });
            }
            @property Loop loop() {
                return _stream.loop;
            }
            @property HttpHeader[] headers() {
                return _headers;
            }
}

class HttpClient 
{
    private:
        TcpStream _stream;

    public:

        this() {
            _stream = new TcpStream;
        }

        HttpResponseMessage get(string uri) {
            return get(Uri(uri));
        }

        HttpResponseMessage get(Uri uri) {
            ushort port = uri.port;
            if(port == 0) {
                port = inferPortForUriSchema(uri.schema);
            }
            _stream.connect4(uri.host, port);
            auto request = new HttpRequestMessage;
            request.method = "GET";
            request.uri = uri;
            request.protocolVersion = HttpVersion(1,0);
            debug writeln("about to send headers");
            request.send(_stream);
            return new HttpResponseMessage(_stream);
        }
}

