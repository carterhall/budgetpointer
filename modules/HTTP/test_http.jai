main :: () {
  server := HTTP.Server.{ host="0.0.0.0" };
  HTTP.add_route(*server, .GET, "/", get_index);
  HTTP.add_route(*server, .GET, "/url_params", get_url_params);

  HTTP.run_server(*server);
}

random_state := Random_State.{1337, 69420};

get_index :: (request: *HTTP.Request) -> HTTP.Response {
  return .{ code=200, body=tprint("Handled! random number %", random_get(*random_state)) };
}

get_url_params :: (request: *HTTP.Request) -> HTTP.Response {
  return .{ code=200, body=tprint("Decoded URL params: %", request.url_params) };
}

#import "Basic";
#import "Random";
#import "String";
HTTP :: #import,file "module.jai";