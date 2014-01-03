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
        server.start ^ (connection) {
            writeln("HTTP Agent just connected");

            connection.process ^ (request, response) {
                writeln("Processing ", request.method, request.rawUri);
                response.write("Hello World from heaploop");
                response.write("something else");
                response.end;
                writeln("Ended");
            };

            writeln("continuing after process");
        };
    };
    writeln("hello world");
}
