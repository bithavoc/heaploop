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
            client.write(cast(ubyte[])"hello world 1 \n");
            client.write(cast(ubyte[])"hello world 2 \n");
            client.read ^ (readStream, data) {
                "read some cool data: ".writeln(data);
                if(data == [10]) {
                    readStream.close;
                }
            };
        };
        writeln("hello world inside ", Loop.current);
    };
    writeln("hello world");
}
