module heaploop.networking.http;
import heaploop.networking.tcp;
import heaploop.networking.dns;
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

class NetworkCredential {
    import std.base64;

    private string _userName, _password;
    public:
        this(string userName = null, string password = null) {
            _userName = userName;
            _password = password;
        }
        this(Uri uri) {
           if(uri.userInfo) {
               auto pieces = uri.userInfo.split(":");
               auto len = pieces.length;
               if(pieces.length > 0) {
                   this(pieces[0], pieces[1]);
                   return;
               }
           } 
           this();
        }
        @property {
            string userName() {
                return _userName;
            }
            void userName(string userName) {
                _userName = userName;
            }
            string password() {
                return _password;
            }
            void password(string password) {
                _password = password;
            }
            string authorizationHeader() {
                return "Basic " ~ cast(string)Base64.encode(cast(ubyte[])(_userName ~ ":" ~ _password));
            }
        }
}

enum HttpParserEventType : ubyte {
    Unknown,
    MessageBegin,
    Url,
    Header,
    HeadersComplete,
    StatusComplete,
    Body,
    MessageComplete
}

struct HttpParserEvent {
        union Store {
             string str; 
             HttpBodyChunk chunk;
             HttpHeader header;
        }

        Store store;
        HttpParserEventType type;
}

abstract class HttpConnectionBase : Looper {
    private:
        TcpStream _stream;
        HttpParser _parser;

        HttpIncomingMessage _currentMessage;

        HttpParserEvent[] _parserEvents;

        void _onMessageBegin(HttpParser p) {
            debug std.stdio.writeln("HTTP message began");
            HttpParserEvent ev;
            ev.type = HttpParserEventType.MessageBegin;
            _parserEvents ~= ev;
        }

        void onUrl(HttpParser p, string uri) {
            HttpParserEvent ev;
            ev.type = HttpParserEventType.Url;
            ev.store.str = _currentMessage.rawUri;
            _parserEvents ~= ev;
        }

        void onHeadersComplete(HttpParser p) {
            HttpParserEvent ev;
            ev.type = HttpParserEventType.HeadersComplete;
            _parserEvents ~= ev;
        }

        void _onStatusComplete(HttpParser parser, string statusLine) {
            HttpParserEvent ev;
            ev.type = HttpParserEventType.StatusComplete;
            ev.store.str = statusLine;
            _parserEvents ~= ev;
        }

        void onBody(HttpParser parser, HttpBodyChunk chunk) {
            HttpParserEvent ev;
            ev.type = HttpParserEventType.Body;
            ev.store.chunk = chunk;
            _parserEvents ~= ev;
        }

        void onHeader(HttpParser p, HttpHeader header) {
            HttpParserEvent ev;
            ev.type = HttpParserEventType.Header;
            ev.store.header = header;
            _parserEvents ~= ev;
        }

        void onMessageComplete(HttpParser p) {
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
        
        void onStatusComplete(string statusLine, uint statusCode) {

        }

        bool _linkProcessing(string requester)() {
            bool isNewMessage = false;
            try {
                debug std.stdio.writeln(requester ~ " Linked to reading to Process HTTP Requests");
                if(!_stream.isOpen) {
                    return false;
                }
                ubyte[] data = _stream.readOnce();
                if(data.length == 0) {
                    return false;
                }
                debug std.stdio.writeln("Readed bytes ", data.length);
                _parserEvents = null;
                _parser.execute(data);
                foreach(ref HttpParserEvent ev; _parserEvents) {
                    switch(ev.type) {
                        case HttpParserEventType.MessageBegin: 
                            _currentMessage = createMessage();
                            onMessageBegin();
                            break;
                        case HttpParserEventType.Url:
                            _currentMessage.rawUri = ev.store.str;
                            _currentMessage.uri = Uri(_currentMessage.rawUri);
                            break;
                        case HttpParserEventType.Header:
                            _currentMessage.addHeader(ev.store.header);
                            break;
                        case HttpParserEventType.HeadersComplete:
                            _currentMessage.protocolVersion = _parser.protocolVersion;
                            _currentMessage.transmissionMode = _parser.transmissionMode;
                            debug std.stdio.writeln("protocol version set, ", _currentMessage.protocolVersion.toString);
                            isNewMessage = true;
                            break;
                        case HttpParserEventType.StatusComplete:
                            onStatusComplete(ev.store.str, _parser.statusCode);
                            break;
                        case HttpParserEventType.Body:
                            auto chunk = ev.store.chunk;
                            debug writeln("HTTP Response Message: read some BODY data (", chunk.buffer.length, " bytes) ", " is final ", chunk.isFinal, ": ", chunk.buffer);
                            debug writeln("onBody ", cast(string)chunk.buffer);
                            if(_currentMessage._isProcessingLinked) {
                                // trigger the body read action directly
                                _currentMessage._readTrigger(chunk);
                                if(chunk.isFinal) {
                                    _currentMessage._isReadingComplete = true;
                                }
                                debug writeln("Chunk delivered directly");
                            } else {
                                // it's the first buffer, save it and unlink processing
                                _currentMessage._bufferedChunk = chunk;
                                debug writeln("Chunk buffered until the incoming message reads");
                            }
                            break;
                    }
                }
            } catch(LoopException lex) {
                if(lex.name == "EOF")  {
                    debug std.stdio.writeln("Connection closed");
                } else {
                    throw lex;
                }
            }
            if(isNewMessage) {
                onBeforeProcess();
                // read
                onProcessMessage();
            }

            static if(requester != "HttpIncomingMessage") {
                debug std.stdio.writeln(requester ~ " HTTP link looping");
                _linkProcessing!requester();
            } else {
                debug std.stdio.writeln(requester ~ " HTTP link completed");
            }
            return true;
        }

    public:
        this(TcpStream stream, HttpParserType parserType) {
            _stream = stream;
            _parser = new HttpParser(parserType);
            _parser.onMessageBegin = &_onMessageBegin;
            _parser.onHeader = &onHeader;
            _parser.onHeadersComplete = &onHeadersComplete;
            _parser.onMessageComplete = &onMessageComplete;
            _parser.onStatusComplete = &_onStatusComplete;
            _parser.onUrl = &onUrl;
            _parser.onBody = &onBody;
        }


        void stop() {
           debug std.stdio.writeln("Stopping connection");
           _stopProcessing();
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
        HttpConnectionBase _connection;
        HttpBodyTransmissionMode _transmissionMode;
    package:

        // first chunk of the body buffer
        HttpBodyChunk _bufferedChunk;
        bool _isProcessingLinked;
        bool _isReadingComplete;

        @property {
            void transmissionMode(HttpBodyTransmissionMode mode) {
                _transmissionMode = mode;
            }
        }

        void delegate(HttpBodyChunk) _readTrigger;


    public:
        this(HttpConnectionBase connection)
            in {
                assert(connection !is null);
            }
            body {
                super(connection.loop);
                this._connection = connection;
            }

            Action!(void, HttpBodyChunk) read() {
                return new Action!(void, HttpBodyChunk)((a) {
                   _readTrigger = a;
                   // if there is a chunk buffered, deliver it
                   if(this._bufferedChunk.buffer.length > 0) {
                        a(this._bufferedChunk);
                        this._bufferedChunk = HttpBodyChunk.init;
                   }
                   _isProcessingLinked = true;
                   while(this.shouldRead && !this._isReadingComplete) {
                       // process connection messages here
                       // so it blocks while reading
                       bool shouldContinueReading = this._connection._linkProcessing!"HttpIncomingMessage"();
                       if(!shouldContinueReading){
                            break;
                       }
                   }
                   _isProcessingLinked = false;
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

            bool shouldRead() {
                writeln("Transmission Mode ", this.transmissionMode, " should read ", this.transmissionMode.shouldRead);
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
                lineWrite("Content-Type: %s".format(_contentType));
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
                    case 422:
                        _statusText = "UNPROCESSABLE ENTITY";
                        break;
                    case 500:
                        _statusText = "INTERNAL SERVER ERROR";
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
                    _linkProcessing!"HttpServerConnection";
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
                _server.listen(backlog) ^= (client) {
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
    string txt = text.data;
    return txt;
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
        NetworkCredential _credentials;

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

            NetworkCredential credentials() {
                return _credentials;
            }
            void credentials(NetworkCredential credentials) {
                _credentials = credentials;
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
            if(_credentials) {
                writeHeader("Authorization: %s".format(_credentials.authorizationHeader));
            }

            ubyte[] entity;
            if(this.content !is null) {
                this.content.writeTo(delegate void(ubyte[] d) {
                    entity ~= d;
                });
                writeHeader("Content-Length: %d".format(entity.length));
                writeHeader("Content-Type: %s".format(this.content.contentType));
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
    private:
        uint _statusCode;

    public:
        this(HttpClientConnection connection)
        {
            super(connection);
        }

        @property {
            uint statusCode() {
                return _statusCode;
            }

            void statusCode(uint code) {
                _statusCode = code;
            }
        }
}

class HttpClientConnection : HttpConnection!HttpResponseMessage {
    alias Action!(void, HttpResponseMessage) responseAction;


    private:
        HttpResponse _currentResponse;
        HttpContext _currentContext;
        void delegate(HttpResponseMessage) _responseCallback;
        responseAction _responseAction;
    
    protected:
         override HttpResponseMessage createIncomingMessage() {
             return new HttpResponseMessage(this);
         }

         override void onMessageBegin() {}

         override void onBeforeProcess() {}
        
         override void onProcessMessage() {
            _responseCallback(currentMessage);
         }

         override void onStatusComplete(string statusLine, uint statusCode) {
            currentMessage.statusCode = statusCode; 
         }
    
    public:
        this(TcpStream stream) {
            super(stream, HttpParserType.RESPONSE);
        }
        
        responseAction response() {
            if(_responseAction is null) {
                _responseAction = new responseAction((trigger) {
                    _responseCallback = trigger;
                    _linkProcessing!"HttpClientConnection"();
                });
            }
            return _responseAction;
        }
}

abstract class HttpContent {
    public:
        abstract void writeTo(void delegate(ubyte[] data) writer);

        @property abstract string contentType();
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

        @property override string contentType() {
            return "application/octet-stream";
        }
}

class FormUrlEncodedContent : UbyteContent {
    public:
        this(string[string] fields) {
            super(cast(ubyte[])encodeURLForm(fields));
        }
        @property override string contentType() {
            return "application/x-www-form-urlencoded";
        }
}

class HttpClient 
{
    private:
        Uri _rootUri;
        NetworkCredential _credentials;
    public:
        this(string rootUri) {
            this(Uri(rootUri));
        }

        this(Uri rootUri) {
            _rootUri = rootUri;
            if(rootUri.userInfo) {
                _credentials = new NetworkCredential(rootUri);
            }
        }

        @property {
            Uri rootUri() nothrow pure {
                return _rootUri;
            }

            NetworkCredential credentials() {
                return _credentials;
            }
        }

        StrictAction!(StrictTrigger.Sync, void, HttpResponseMessage) send(string method, string path, HttpContent content = null) {
            return new StrictAction!(StrictTrigger.Sync, void, HttpResponseMessage)((trigger) {
                Uri uri = Uri(_rootUri.toString ~ path);
                ushort port = uri.port;
                if(port == 0) {
                    port = inferPortForUriSchema(uri.schema);
                }
                TcpStream stream = new TcpStream;
                debug writeln("HOST ", uri.host, port);
                stream.connect(uri.host, port);
                auto request = new HttpRequestMessage;
                request.credentials = _credentials;
                request.method = method;
                request.uri = uri;
                request.protocolVersion = HttpVersion(1,0);
                request.content = content;
                request.send(stream);
                auto connection = new HttpClientConnection(stream);
                HttpResponseMessage response;
                connection.response ^= (r) {
                    trigger(r);
                };
            });
        }

        StrictAction!(StrictTrigger.Sync, void, HttpResponseMessage) post(string path, HttpContent content = null) {
            return send("POST", path, content);
        }

        StrictAction!(StrictTrigger.Sync, void, HttpResponseMessage) post(string path, string[string] fields) {
            return post(path, new FormUrlEncodedContent(fields));
        }

        StrictAction!(StrictTrigger.Sync, void, HttpResponseMessage) put(string path, HttpContent content = null) {
            return send("PUT", path, content);
        }

        StrictAction!(StrictTrigger.Sync, void, HttpResponseMessage) get(string path) {
            return new StrictAction!(StrictTrigger.Sync, void, HttpResponseMessage)((trigger) {
                Uri uri = Uri(_rootUri.toString ~ path);
                ushort port = uri.port;
                if(port == 0) {
                    port = inferPortForUriSchema(uri.schema);
                }
                TcpStream stream = new TcpStream;
                debug writeln("HOST ", uri.host, port);
                stream.connect(uri.host, port);
                auto request = new HttpRequestMessage;
                request.credentials = _credentials;
                request.method = "GET";
                request.uri = uri;
                request.protocolVersion = HttpVersion(1,0);
                request.send(stream);
                auto connection = new HttpClientConnection(stream);
                HttpResponseMessage response;
                connection.response ^= (r) {
                    trigger(r);
                    //connection.stop;
                };
            });
        }
}

