import heaploop.networking.http;
import std.stdio : writeln;

unittest {
    scope(exit) {
        writeln("Forms Tests Finished");
    }
    {
       FormFields fields = parseURLEncodedForm(null); 
       assert(fields.length == 0);
    }
    {
       FormFields fields = parseURLEncodedForm(""); 
       assert(fields.length == 0);
    }
    {
       FormFields fields = parseURLEncodedForm("one=1"); 
       assert(fields.length == 1);
       assert("one" in fields);
       assert(fields["one"] == "1");
    }
    {
       FormFields fields = parseURLEncodedForm("my+%22message%22=this+is+my+social+handle%3A+%23thepumpkin&hello=world"); 
       assert(fields.length == 2);
       assert("my \"message\"" in fields);
       assert(fields["my \"message\""] == "this is my social handle: #thepumpkin");
       assert("hello" in fields);
       assert(fields["hello"] == "world");
    }
    {
       FormFields fields;
       string message = encodeURLForm(fields); 
       assert(message is null);
    }
    {
       FormFields fields = ["one":"1"];
       string message = encodeURLForm(fields); 
       assert(message == "one=1");
    }
    {
       FormFields fields = [ "my \"message\"" : "this is my social handle: #thepumpkin", "hello" : "world" ];
       string message = encodeURLForm(fields);
       writeln(message);
       assert(message == "hello=world&my+%22message%22=this+is+my+social+handle%3A+%23thepumpkin");
    }
}
