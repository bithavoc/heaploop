module loop_example;

import heaploop.looping;
import heaploop.networking.tcp;

import std.stdio;

void main() {
    loop ^ {
        auto server = new TcpStream;
        server.bind4("0.0.0.0", 3000);
        "bound".writeln;
        "listening localhost:3000".writeln;
        server.listen(50000);
        while(true) {
            auto client = server.accept;
            writeln("New client has arrived");
            client.write(cast(ubyte[])"hello world 1 \n");
            client.write(cast(ubyte[])"hello world 2 \n");
            try {
                while(true) {
                    ubyte[] data = client.read;
                    "read some cool data: ".writeln(data);
                    if(data == [10]) {
                        break;
                    }
                }
            } catch(Exception readEx) {
                writeln("read error: ", readEx.msg);
            }
            writeln("continuing after read");
        }
    };
    writeln("hello world");
}
