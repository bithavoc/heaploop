module http_example;

import heaploop.looping;
import heaploop.networking.http;

import std.stdio;
void main() {
    loop ^ {
        auto server = new HttpListener;
        server.bind4("0.0.0.0", 3000);
        "bound".writeln;
        "listening http://localhost:3000".writeln;
            server.accept((connection) {
                new core.thread.Fiber(() {

                        debug writeln("HTTP Agent just connected");

                        connection.process ^ (request, response) {
                        debug writeln("Processing ", request.method, request.rawUri, " as protocol version ", request.protocolVersion.toString);
                        foreach(h;request.headers) {
                        debug writeln("Header ", h.name, h.value);
                        }
                        response.write("Hello World from heaploop\r\n");
                        response.write("something else\r\n");
                        response.end;
                        debug writeln("Ended processing");
                        };

                        debug writeln("continuing after process");
                }).call;
                //core.memory.GC.collect;
                //core.memory.GC.minimize;
            });
    };
    writeln("hello world");
}
