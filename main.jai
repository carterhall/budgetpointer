conn: *Postgres.PGconn = null;

main :: () {
  print("Connecting to database...\n");
  DB_URL := "postgres://postgres:postgres@localhost:5432/postgres";
  success := false;
  conn, success = Postgres.connect_synchronous(DB_URL);
  defer Postgres.disconnect(conn);

  server := HTTP.Server.{ host = "0.0.0.0" };

  HTTP.add_route(*server, .GET, "/",  get_index);
  HTTP.add_route(*server, .POST, "/", post_index);

  HTTP.add_route(*server, .GET,  "/join",  get_join);
  HTTP.add_route(*server, .POST, "/join",  post_join);

  HTTP.run_server(*server);
}

PAGE_HTML :: #string END_HTML
<html>
  <head>
    <meta charset="UTF-8" />
    <link rel="stylesheet" href="https://unpkg.com/98.css" />
    <script src="https://unpkg.com/htmx.org@1.9.12"></script>
  </head>
  <body style="background-color: #30a9c7;">
    %
  </body>
</html>
END_HTML

INDEX_HTML :: #string END_HTML
<div class="window" style="margin: 0 auto; max-width: 1000px">
  <div class="title-bar">
    <div class="title-bar-text">Welcome To My Channel</div>
  </div>
  <div class="window-body">
    <p id="user-list">Users: %</p>

    <form hx-post="/" hx-target="#user-list" hx-swap="outerHTML">
      <input name="first_name" placeholder="First Name">
      <input name="last_name" placeholder="Last Name">
      <button type="submit">Add User</button>
    </form>
  </div>
</div>
END_HTML

USER_LIST_HTML :: #string END_HTML
    <p id="user-list">Users: %</p>
END_HTML

NEW_SESSION_HTML :: #string END_HTML
<div class="window" style="margin: 0 auto; max-width: 1000px">
  <div class="title-bar">
    <div class="title-bar-text">Welcome To My Channel</div>
  </div>
  <div class="window-body">
    <p id="user-list">Users: %</p>

    <form hx-post="/" hx-target="#user-list" hx-swap="outerHTML">
      <input name="first_name" placeholder="First Name">
      <input name="last_name" placeholder="Last Name">
      <button type="submit">Add User</button>
    </form>
  </div>
</div>
END_HTML

User :: struct { 
  first_name, last_name: string; 
}

render_index :: () -> string {
  results, success := Postgres.execute(conn, User, "SELECT first_name, last_name FROM users;");
  return sprint(PAGE_HTML, sprint(INDEX_HTML, results));
}

render_user_list_only :: () -> string {
  results, success := Postgres.execute(conn, User, "SELECT first_name, last_name FROM users;");
  return sprint(USER_LIST_HTML, results);
}

get_index :: (request: *HTTP.Request) -> HTTP.Response {
  response: HTTP.Response;
  response.code = 200;

  print("URL params: %\n", request.url_params);

  templated := render_index();
  defer free(templated.data);
  response.body = copy_string(templated);
  return response;
}

parse_url_encoded :: (params: string) -> Table(string, string) {
  result: Table(string, string);
  paramset := split(params, "&");
  for paramset {
    found, key, value := split_from_left(it, "=");
    if found {
      //key   = decode_uri_component(key);
      //value = decode_uri_component(value);
      key   = HTTP.percent_decode(key);
      value = HTTP.percent_decode(value);
      table_add(*result, key, value);
    } else {
      log_error("Problematic parameter '%'\n", it);
    }
  }
  return result;
}

post_index :: (request: *HTTP.Request) -> HTTP.Response {
  response: HTTP.Response;
  response.code = 200;
  
  url_params := parse_url_encoded(request.body);

  first_name := "";
  last_name := "";
  found := false;
  first_name, found = table_find(*url_params, "first_name");
  last_name, found = table_find(*url_params, "last_name");
  results, success := Postgres.execute(conn, User, tprint("INSERT INTO users (first_name, last_name) VALUES('%', '%');", first_name, last_name));

  templated := render_user_list_only();
  defer free(templated.data);
  response.body = copy_string(templated);
  return response;
}

//#import "SimpleHTTP"(USE_MIDDLEWARE=false);
HTTP :: #import "HTTP";
Postgres :: #import "Postgres";

#import "Hash_Table";
#import "String";
#import "Basic";
