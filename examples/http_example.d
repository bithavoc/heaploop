module http_example;

import heaploop.looping;
import heaploop.networking.http;

import std.stdio;
void main() {
    loop ^^ {
        new Check().start((c){
           // Garbage Collect on every loop
           //core.memory.GC.collect;
        });
        auto server = new HttpListener;
        server.bind4("0.0.0.0", 3000);
        "bound".writeln;
        "listening http://localhost:3000".writeln;
        server.listen ^^ (connection) {
            debug writeln("HTTP Agent just connected");
            try {
                connection.process ^^ (request, response) {
                    try {
                        debug writeln("Processing ", request.method, " ",  request.uri.path, " as protocol version ", request.protocolVersion.toString);
                        foreach(h;request.headers) {
                            debug writeln("Header ", h.name, h.value);
                        }
                        response.write("Hello World from heaploop\r\n");
                        response.write("something else\r\n");
                        response.end;
                        debug writeln("Ended processing");
                    } catch(Exception ex) {
                        debug writeln("Error processing HTTP in the example app", ex);
                    }
                };
            } catch(Exception ex) {
                debug writeln("something went wrong processing http in dis conn");
            } finally {
                debug writeln("Error happended in http example, stopping connection");
                //connection.stop;
            }
            debug writeln("continuing after process");
            //core.memory.GC.collect;
            //core.memory.GC.minimize;
        };
        writeln("no longer listening");
    };
    writeln("hello world");
}
