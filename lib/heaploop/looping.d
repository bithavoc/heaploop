module heaploop.looping;

import events;

EventList!void loop() {
    auto event = new EventList!void;
    auto trigger = event.own;
    trigger.changed = (op, item) {
            if(op == EventListOperation.Added) {
                trigger();
            }
    };
    return event;
}
