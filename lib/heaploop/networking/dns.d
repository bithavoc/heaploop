module heaploop.networking.dns;
import duv.c;
import duv.types;
import heaploop.looping;

public import duv.c : Address, Internet6Address, InternetAddress;

class DnsClient : Looper {

    private:
        Loop _loop;
        class resolveOperation : OperationContext!DnsClient {
            public:
                Address[] addresses;
                this(DnsClient client) {
                    super(client);
                }
        }

    public:
        this(Loop loop = Loop.current) {
            _loop = loop;
        }

        @property Loop loop() {
            return _loop;
        }

        public Address[] resolveHost(string host) {
            auto wc = new resolveOperation(this);
            duv_getaddrinfo(this.loop.handle, wc, host, null, function (ctx, status, addrInfos) {
                    auto wc = cast(resolveOperation)ctx;
                    if(addrInfos !is null) {
                        foreach(addrInfo; addrInfos) {
                            wc.addresses ~= addrInfo.address;
                        }
                    }
                    wc.update(status);
                    wc.resume();
            });
            scope (exit) delete wc;
            wc.yield;
            wc.completed;
            return wc.addresses;
        }
}

class Dns {
    public:
        static Address[] resolveHost(string host) {
            return new DnsClient().resolveHost(host);
        }
}
