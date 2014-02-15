module http_serv;

import heaploop.looping;
import heaploop.networking.http;
import std.string;
import std.stdio;
import std.typecons;


alias Tuple!(int, string[string], string[]) RackResponse;

interface RackApp {
  RackResponse call(string[string] env);
}

class RackAdapter {
  private:
    RackApp _app;

  public:
      this(RackApp app) {
          _app = app;
      }

      void handleRequest(HttpRequest req, HttpResponse res) {
          string[string] env = requestToEnv(req);
          RackResponse response = _app.call(env);
          sendResponse(res, response);
      }

  private:
      string[string] requestToEnv(HttpRequest request) {
          string[string] environment;

          environment["HTTP_VERSION"] = request.protocolVersion.toString;
          environment["REQUEST_METHOD"] = request.method;
          environment["REQUEST_URI"] = request.rawUri;
          environment["REQUEST_PATH"] = request.uri.path;
          environment["SCRIPT_NAME"] = "";
          environment["PATH_INFO"] = request.uri.path;
          environment["QUERY_STRING"] = request.uri.query;
          environment["FRAGMENT"] = request.uri.fragment;

          string headerKey;
          auto transTable = makeTrans("-", "_");
          foreach(h; request.headers) {
              headerKey = "HTTP_%s".format(h.name.toUpper.translate(transTable));
              environment[headerKey] = h.value;
          }
          return environment;
      }

      void sendResponse(HttpResponse response, RackResponse rackResponse) {
          response.statusCode(rackResponse[0]);
          foreach(string header, string value; rackResponse[1]) {
              response.addHeader(header, value);
          }
          foreach(string chunk; rackResponse[2]) {
              response.write(chunk);
          }
          response.end;
      }
}

class HelloApp : RackApp {
    RackResponse call(string[string] env) {
        string[string] headers;
        string[] resBody;

        headers["Content-Type"] = "text/plain";
        resBody ~= "Hello, World!";

        return RackResponse(200, headers, resBody);
    }
}

void main() {
    loop ^^= {
        auto server = new HttpListener;
        server.bind4("0.0.0.0", 3000);
        writeln("listening on http://localhost:3000");
        server.listen ^^= (connection) {
            try {
                auto app = new HelloApp;
                auto adapter = new RackAdapter(app);
                connection.process ^^= (&adapter.handleRequest);
            } catch(Exception ex) {
                writeln("something went wrong processing http in this connection");
            }
        };
    };
}
