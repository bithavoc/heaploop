module loop_example;

import heaploop.looping;
import std.stdio;

void main() {
    loop ^ {
        writeln("hello world inside ", Loop.current);
    };
    writeln("hello world");
}
