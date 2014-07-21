import heaploop.looping;
import heaploop.networking.http;
import core.thread;
import std.stdio;
import std.string : format;

void main() {
    loop ^^= {
        try {
            writeln("HTTP Client Example: Sending Request");
            //HttpClient client = new HttpClient("http://www.google.com");
            HttpClient client = new HttpClient("http://scontent-a-mia.xx.fbcdn.net/hphotos-xpf1/v/t1.0-9/10489917_10152205498466850_4999344580651633437_n.jpg?oh=be8c9a6002fb6eb15ba8091d31ce9bcf&oe=543829AC");
            client.get("/hello") ^= (response) {
                writeln("HTTP Client Example: Response received, reading body");
                foreach(h; response.headers) {
                    writeln("=> %s : %s".format(h.name, h.value)); 
                }
                response.read ^= (chunk) {
                   writeln("HTTP Response Body: ", cast(string)chunk.buffer); 
                };
                writeln("Finished reading");
            };
        } catch(Throwable tex) {
            writeln("App general error: ", tex);
        }
    };
}
