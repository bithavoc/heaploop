import heaploop.looping;
import heaploop.networking.tcp;
import std.stdio;

void main() {
    writeln("Connecting to 0.0.0.0:3000");
    loop ^^= {
        TcpStream stream = new TcpStream;
        stream.connect4("0.0.0.0", 3000);
        stream.read ^= (data) {
            writeln("Bytes Read from Server: ", data.length);
        };
    };
}
