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
       FormFields fields = parseURLEncodedForm("my+%22message%22=this+is+my+social+handle%3A+%23thepumpkin"); 
       assert(fields.length == 1);
       assert("my \"message\"" in fields);
       assert(fields["my \"message\""] == "this is my social handle: #thepumpkin");
    }
}
