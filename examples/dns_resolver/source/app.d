import std.stdio;
import heaploop.looping;
import heaploop.networking.dns;

void main()
{
    loop ^^= {
        auto addresses = Dns.resolveHost("google.com");
        foreach(addr; addresses) {
            writefln("Address is %s", addr.toAddrString); 
        }
	    writeln("Edit source/app.d to start your project.");
    };
}
