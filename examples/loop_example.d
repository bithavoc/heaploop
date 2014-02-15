module loop_example;

import heaploop.looping;
import heaploop.networking.tcp;

import std.stdio;

void main() {
    try {
        loop ^^= {
            new Check().start((c){
                writeln("Collect begin");
                core.memory.GC.collect;
                core.memory.GC.minimize;
                writeln("Collect finished");
            });
            auto server = new TcpStream;
            server.bind4("0.0.0.0", 3000);
            "bound".writeln;
            "listening localhost:3000".writeln;
            server.listen(50000) ^= (client) {
                    writeln("New client has arrived");
                    writeln("Writing something");
                    client.write(cast(ubyte[])"hello world 1 \n");
                    client.write(cast(ubyte[])"hello world 2 \n");
                    writeln("Reading something");
                    try {
                        client.read ^= (data) {
                            "read some cool data: ".writeln(data);
                            if(data == [10]) {
                                client.close;
                            }
                        };
                    } catch(Exception readEx) {
                        writeln("read error: ", readEx.msg);
                    }
                    writeln("continuing after read");
            };
        };
    } catch(Exception ex) {
        writeln("accept loop error: ", ex);
    }
    writeln("hello world");
}
