module heaploop.networking.http;
import heaploop.networking.tcp;
import heaploop.looping;
import heaploop.streams;
import events;
import std.string : format, translate;
import std.array : split, appender, replace;
import std.uri : decodeComponent, encodeComponent;
import http.parser.core;

debug {
    import std.stdio : writeln;
}

/*
 * HTTP Common
 */

abstract class HttpConnectionBase : Looper {
    private:
        TcpStream _stream;
        HttpParser _parser;

        HttpIncomingMessage _currentMessage;

        void _onMessageBegin(HttpParser p) {
            debug std.stdio.writeln("HTTP message began");
            _currentMessage = createMessage();
            onMessageBegin();
        }

        void onUrl(HttpParser p, string uri) {
            _currentMessage.rawUri = uri;
            _currentMessage.uri = Uri(_currentMessage.rawUri);
        }

        void onHeadersComplete(HttpParser p) {
            _currentMessage.protocolVersion = p.protocolVersion;
            _currentMessage.transmissionMode = p.transmissionMode;
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
        final {
            @property {
                HttpIncomingMessage currentMessage() nothrow pure {
                    return _currentMessage;
                }

                HttpParser parser() nothrow pure {
                    return _parser;
                }
            }
        }

        abstract HttpIncomingMessage createMessage();

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

abstract class HttpConnection(TIncomingMessage : HttpIncomingMessage) : HttpConnectionBase {
    protected:
        abstract TIncomingMessage createIncomingMessage();

        override HttpIncomingMessage createMessage() {
            return createIncomingMessage();
        }

        @property TIncomingMessage currentMessage() {
            return cast(TIncomingMessage)super.currentMessage;
        }
        alias HttpConnectionBase.currentMessage currentMessage;
    public:

        this(TcpStream stream, HttpParserType parserType) {
            super(stream, parserType);
        }

}

abstract class HttpMessage : Looper {
    private:
        Loop _loop;
        HttpHeader[] _headers;
        HttpVersion _version;
        string _contentType;

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

            string contentType() {
                return _contentType;
            }
        }

        void addHeader(HttpHeader header) {
            _headers ~= header;
            if(header.name == "Content-Type") {
                _contentType = header.value;
            }
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
        HttpConnectionBase connection;
        HttpBodyTransmissionMode _transmissionMode;
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
        @property {
            void transmissionMode(HttpBodyTransmissionMode mode) {
                _transmissionMode = mode;
            }
        }


    public:
        this(HttpConnectionBase connection)
            in {
                assert(connection !is null);
            }
            body {
                super(connection.loop);
            }

            Action!(void, HttpBodyChunk) read() {
                return new Action!(void, HttpBodyChunk)((a) {
                   if(this.shouldRead) {
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
                   }
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

            bool shouldRead() nothrow pure {
                return this.transmissionMode.shouldRead;
            }

            HttpBodyTransmissionMode transmissionMode() nothrow pure {
                return _transmissionMode;
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

        this(HttpServerConnection connection) {
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
        HttpServerConnection _connection;
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
        this(HttpServerConnection connection) {
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
                    case 201:
                        _statusText = "CREATED";
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

class HttpServerConnection : HttpConnection!HttpRequest {
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
            currentMessage.method = this.parser.method;
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

    protected:
        HttpServerConnection createConnection(TcpStream stream) {
            return new HttpServerConnection(stream);
        }

    public:
        this() {
            _server = new TcpStream;
        }

        TThis bind4(this TThis)(string address, int port) {
            _server.bind4(address, port);
            return cast(TThis)this;
        }

        Action!(void, HttpServerConnection) listen(int backlog = 50000) {
            return new Action!(void, HttpServerConnection)((trigger) {
                _server.listen(backlog) ^ (client) {
                    auto connection = this.createConnection(client);
                    trigger(connection);
                };
            });
        }

}

alias string[string] FormFields;

private:

static dchar[dchar] FormDecodingTranslation;

static this() {
    FormDecodingTranslation = ['+' : ' '];
}

string decodeFormComponent(string component) {
    return component.translate(FormDecodingTranslation);
}

string encodeFormComponent(string component) {
    return component.replace("%20", "+");
}

public:

FormFields parseURLEncodedForm(string content) {
    if(content.length < 1) return null;
    FormFields fields;
    string[] pairs = content.split("&");
    foreach(entry; pairs) {
        string[] values = entry.split("=");
        string name = values[0].decodeComponent.decodeFormComponent;
        string value = values[1];
        fields[name] = value.decodeComponent.decodeFormComponent;
    }
    return fields;
}

string encodeURLForm(FormFields fields) {
    if(fields.length < 1) return null;
    auto text = appender!string;
    foreach(i, name;fields.keys) {
        if(i != 0) {
            text.put("&");
        }
        text.put(name.encodeComponent.encodeFormComponent);
        text.put("=");
        text.put(fields[name].encodeComponent.encodeFormComponent);
    }
    return text.data;
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
        HttpContent _content;

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

            HttpContent content() {
                return _content;
            }
            void content(HttpContent content) {
                _content = content;
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

            ubyte[] entity;
            if(this.content !is null) {
                this.content.writeTo(delegate void(ubyte[] d) {
                    entity ~= d;
                });
                writeHeader("Content-Length: %d".format(entity.length));
            }
            writeHeader("");
            if(entity.length > 0) {
                stream.write(entity);
            }
            debug writeln("headers send");
        }
}

class HttpResponseMessage : HttpIncomingMessage
{
    public:
        this(HttpClientConnection connection)
        {
            super(connection);
        }
}

class HttpClientConnection : HttpConnection!HttpResponseMessage {
    alias Action!(void, HttpResponseMessage) processEventList;


    private:
        HttpResponse _currentResponse;
        HttpContext _currentContext;
        void delegate(HttpResponseMessage) _responseCallback;
        processEventList _responseAction;
    
    protected:
         override HttpResponseMessage createIncomingMessage() {
             return new HttpResponseMessage(this);
         }

         override void onMessageBegin() {}

         override void onBeforeProcess() {}
        
         override void onProcessMessage() {
            _responseCallback(currentMessage);
         }
    
    public:
        this(TcpStream stream) {
            super(stream, HttpParserType.RESPONSE);
        }
        
        processEventList response() {
            if(_responseAction is null) {
                _responseAction = new processEventList((trigger) {
                    _responseCallback = trigger;
                    startProcessing();
                });
            }
            return _responseAction;
        }
}

abstract class HttpContent {
    public:
        abstract void writeTo(void delegate(ubyte[] data) writer);
}

class UbyteContent: HttpContent {
    private:
        ubyte[] _buffer;

    public:
        this(ubyte[] buffer) {
            _buffer = buffer;
        }

        override void writeTo(void delegate(ubyte[] data) writer) {
            if(_buffer !is null) {
                writer(_buffer);
            }
        }
}

class FormUrlEncodedContent : UbyteContent {
    public:
        this(string[string] fields) {
            super(cast(ubyte[])encodeURLForm(fields));
        }
}

class HttpClient 
{
    private:
        Uri _rootUri;
    public:
        this(string rootUri) {
            this(Uri(rootUri));
        }

        this(Uri rootUri) {
            _rootUri = rootUri;
        }

        @property {
            Uri rootUri() nothrow pure {
                return _rootUri;
            }
        }

        HttpResponseMessage send(string method, string path, HttpContent content = null) {
            Uri uri = Uri(_rootUri.toString ~ path);
            ushort port = uri.port;
            if(port == 0) {
                port = inferPortForUriSchema(uri.schema);
            }
            TcpStream stream = new TcpStream;
            stream.connect4(uri.host, port);
            auto request = new HttpRequestMessage;
            request.method = method;
            request.uri = uri;
            request.protocolVersion = HttpVersion(1,0);
            request.content = content;
            request.send(stream);
            auto connection = new HttpClientConnection(stream);
            HttpResponseMessage response;
            connection.response ^ (r) {
                response = r;
                connection.stop;
            };
            return response;
        }

        HttpResponseMessage post(string path, HttpContent content = null) {
            return send("POST", path, content);
        }

        HttpResponseMessage put(string path, HttpContent content = null) {
            return send("PUT", path, content);
        }

        HttpResponseMessage get(string path) {
            Uri uri = Uri(_rootUri.toString ~ path);
            ushort port = uri.port;
            if(port == 0) {
                port = inferPortForUriSchema(uri.schema);
            }
            TcpStream stream = new TcpStream;
            stream.connect4(uri.host, port);
            auto request = new HttpRequestMessage;
            request.method = "GET";
            request.uri = uri;
            request.protocolVersion = HttpVersion(1,0);
            request.send(stream);
            auto connection = new HttpClientConnection(stream);
            HttpResponseMessage response;
            connection.response ^ (r) {
                response = r;
                connection.stop;
            };
            return response;
        }
}

