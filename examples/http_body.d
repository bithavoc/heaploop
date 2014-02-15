import heaploop.looping;
import heaploop.networking.http;
import core.thread;
import std.stdio;
import std.string : format;

void main() {
    loop ^^= {
        HttpListener server = new HttpListener;
        server.bind4("0.0.0.0", 3000);
        server.listen ^^= (connection) {
            writeln("New HTTP connection");
            connection.process ^^= (request, response) {
                if(request.method == "POST") {
                    writeln("Serveing POST");
                    request.read ^ (chunk) {
                        writeln("POST Chunk ", cast(string)chunk.buffer);
                    };
                    writeln("request.read completed");
                }
                response.addHeader("X-Server", "Heaploop HTTPClient Example 1.1");
                writeln("Serving response ", request.uri.path);
                response.write("Hello World");
                response.write("Hello World Part II");
                response.end;
                writeln("Served!");
            };
        };
    };
}
