module heaploop.networking.dns;
import duv.c;
import duv.types;
import heaploop.looping;
import std.string : toStringz;

private:
public:

enum AddressFamily {
    None,
    INETv4,
    INETv6
}

class NetworkAddress {
    private:
        string _ip;
        int _port;
        AddressFamily _family;

    package:
        this(string ip, int port, AddressFamily family) {
            _ip = ip;
            _port = port;
            _family = family;
        }

    public:

        @property{

            string IP() {
                return _ip;
            }

            int port() {
                return _port;
            }

            AddressFamily family() {
                return _family;
            }
        }
}



class DnsClient : Looper {

    private:
        Loop _loop;
        class resolveOperation : OperationContext!DnsClient {
            public:
                NetworkAddress[] addresses;
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

        public NetworkAddress[] resolveHost(string host) {
            auto wc = new resolveOperation(this);
            duv_getaddrinfo(this.loop.handle, wc, host, null, function (ctx, status, duv_addresses) {
                    auto wc = cast(resolveOperation)ctx;
                    if(duv_addresses !is null) {
                        foreach(addr; duv_addresses) {
                            AddressFamily family = void;
                            switch(addr.family) {
                                case duv_addr_family.INETv4:
                                    family = AddressFamily.INETv4;
                                break;
                                case duv_addr_family.INETv6:
                                    family = AddressFamily.INETv6;
                                break;
                                default:
                                    assert(0, "Unknown address family, failure in uv.d?");
                            }
                            NetworkAddress address = new NetworkAddress(addr.ip, 0, family);
                            wc.addresses ~= address;
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
        static NetworkAddress[] resolveHost(string host) {
            return new DnsClient().resolveHost(host);
        }
}
