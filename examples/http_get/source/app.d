import heaploop.looping;
import heaploop.networking.http;
import core.thread;
import std.stdio;
import std.string : format;

void main() {
    loop ^^= {
        writeln("HTTP Client Example: Sending Request");
        HttpClient client = new HttpClient("http://google.com:80");
        auto response = client.get("/hello");
        writeln("HTTP Client Example: Response received, reading body");
        foreach(h; response.headers) {
            writeln("=> %s : %s".format(h.name, h.value)); 
        }
        response.read ^= (chunk) {
           writeln("HTTP Response Body: ", cast(string)chunk.buffer); 
        };
        writeln("Finished reading");
    };
}
