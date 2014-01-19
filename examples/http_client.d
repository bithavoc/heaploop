import heaploop.looping;
import heaploop.networking.http;
import core.thread;
import std.stdio;
import std.string : format;

void main() {
    loop ^^ {
        new Fiber({
            HttpListener server = new HttpListener;
            server.bind4("0.0.0.0", 4000);
            server.listen ^^ (connection) {
                writeln("New HTTP connection");
                connection.process ^^ (request, response) {
                    writeln("Serving response ", request.uri.path);
                    response.write("Hello World");
                    response.write("Hello World Part II");
                    response.end;
                    writeln("Served!");
                };
            };
        }).call;
        writeln("HTTP Client Example: Sending Request");
        HttpClient client = new HttpClient;
        auto response = client.get("http://0.0.0.0:4000/hello");
        writeln("HTTP Client Example: Response received, reading body");
        foreach(h; response.headers) {
            writeln("=> %s : %s".format(h.name, h.value)); 
        }
        response.read ^ (read) {
           writeln("HTTP Response Body: ", cast(string)read); 
        };
        writeln("Finished reading");
    };
}