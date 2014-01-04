module heaploop.networking.http;
import heaploop.networking.tcp;
import heaploop.looping;
import heaploop.streams;
import events;
import std.string : format;
import http.parser.core;


class HttpRequest {
    private:
        string _rawUri;
        string _method;
        HttpHeader[] _headers;

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

}

class HttpResponse {
    private:
        HttpConnection _connection;
        bool _headersSent;
        uint _statusCode;
        string _statusText;
        string _contentType;

        void lineWrite(string data = "") {
            _connection.stream.write(cast(ubyte[])(data ~ "\r\n"));
        }

        void _ensureHeadersSent() {
            if(!headersSent) {
                auto stream = _connection.stream;
                lineWrite("HTTP/1.1 %d %s".format(_statusCode, _statusText));
                lineWrite("Content-Type: %s; charset=UTF-8".format(_contentType));
                lineWrite("Transfer-Encoding: chunked");
                lineWrite("Connection: close");
                lineWrite();
                _headersSent = true;
            }
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

        void write(ubyte[] data) {
            _ensureHeadersSent();
            _connection.stream.write((cast(ubyte[])format("%x\r\n", data.length)));
            _connection.stream.write(data ~ cast(ubyte[])"\r\n");
        }

        void write(string data) {
            write(cast(ubyte[])data);
        }

        void end() {
            _ensureHeadersSent();
            write(cast(ubyte[])[]);
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

        void onMessageBegin(HttpParser p) {
            debug std.stdio.writeln("HTTP message began");
            _currentRequest = new HttpRequest;
            _currentResponse = new HttpResponse(this);
        }

        void onUrl(HttpParser p, string uri) {
            _currentRequest.rawUri = uri;
        }

        void onStatus(HttpParser p, string status) {
        }

        void onHeadersComplete(HttpParser p) {
            _currentRequest.method = p.method;
        }

        void onHeader(HttpParser p, HttpHeader header) {
            _currentRequest.addHeader(header);
        }

        void onMessageComplete(HttpParser p) {
            _processTrigger(_currentRequest, _currentResponse);
        }

        void _startProcessing() {
            try {
                _stream.read ^ (stream, data) {
                    debug std.stdio.writeln("HttpConnection Read: ", cast(string)data);
                    _parser.execute(data);
                };
            } catch(LoopException lex) {
                if(lex.name == "EOF")  {
                    debug std.stdio.writeln("Connection closed");
                } else {
                    throw lex;
                }
            }
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
    alias FiberedEventList!(void, HttpConnection) startEventList;
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
