module loop_example;

import heaploop.looping;
import heaploop.networking.tcp;

import std.stdio;

void main() {
    loop ^ {
        auto server = new TcpStream;
        server.bind4("0.0.0.0", 3000);
        server.listen ^ (client) {
            writeln("New client has arrived");
        };
        writeln("hello world inside ", Loop.current);
    };
    writeln("hello world");
}
