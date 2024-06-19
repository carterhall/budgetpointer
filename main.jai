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

  HTTP.add_route(*server, .GET, "/session", get_session);
  HTTP.add_route(*server, .GET, "/session_data", get_session_data);

  HTTP.add_route(*server, .GET, "/rickrolled", get_rickrolled);

  HTTP.add_route(*server, .POST, "/new", post_new);

  HTTP.add_route(*server, .GET,  "/join", get_join);
  HTTP.add_route(*server, .POST, "/join", post_join);

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
<div class="window" style="margin: 0 auto; max-width: 600px">
  <div class="title-bar">
    <div class="title-bar-text">Welcome</div>
  </div>
  <div class="window-body">
    <button hx-post="/new">Create Pointing Session</button>
  </div>
</div>
END_HTML

SESSION_HTML :: #string END_HTML
<div class="window" style="margin: 0 auto; max-width: 600px">
  <div class="title-bar">
    <div class="title-bar-text">Please Donate I Beg You</div>
  </div>
  <div class="window-body">
    <button hx-get="/rickrolled">Donate $1</button>
  </div>
</div>
<br><br>
<div class="window" style="margin: 0 auto; max-width: 600px">
  <div class="title-bar">
    <div class="title-bar-text">Emma Zone</div>
  </div>
  <div class="window-body">
    <button hx-post="/new">Clear Votes</button>
    <button hx-post="/new">Show Votes</button>
    <button hx-post="/new">Force Consensus</button>
  </div>
</div>
<br><br>
<div class="window" style="margin: 0 auto; max-width: 600px">
  <div class="title-bar">
    <div class="title-bar-text">Pointing Session %</div>
  </div>
  <div class="window-body">
    <button hx-post="/vote">1</button>
    <button hx-post="/vote">2</button>
    <button hx-post="/vote">3</button>
    <button hx-post="/vote">5</button>
    <button hx-post="/vote">8</button>
    <button hx-post="/vote">13</button>
    <button hx-post="/vote">21</button>
    <button hx-post="/vote">34</button>
    <button hx-post="/vote">55</button>
    <button hx-post="/vote">I Recuse Myself</button>
    <button hx-post="/vote">I Don't Understand</button>
    <button hx-post="/vote">I Zoned Out</button>
    <p>Results:</p>
    <p hx-get="/session_data" hx-trigger="every 0.25s">
      Soon to be gone...
    </p>
  </div>
  <div class="status-bar">
    <p class="status-bar-field">Press F1 for help</p>
    <p class="status-bar-field">Slide 1</p>
    <p class="status-bar-field">CPU Usage: 14%</p>
  </div>
</div>
END_HTML

SESSION_DATA_HTML :: #string END_HTML
  <p hx-get="/session_data" hx-trigger="every 2s">
    %
  </p>
END_HTML

USER_LIST_HTML :: #string END_HTML
    <p id="user-list">Users: %</p>
END_HTML

RICKROLL_HTML :: #string END_HTML
  <iframe width="560" height="315" src="https://www.youtube.com/embed/wpV-gGA4PSk?si=tlPJZJNIZ8xLjTD4" title="YouTube video player" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" referrerpolicy="strict-origin-when-cross-origin" allowfullscreen></iframe>
END_HTML

User :: struct { 
  first_name, last_name: string; 
}

random_state := Random_State.{1337, 69420};

get_session :: (request: *HTTP.Request) -> HTTP.Response {
  session_id, found := table_find(*request.url_params, "sessionId");
  if !found {
    return .{ code=302, headers=.[.{"Location", "/"}]};
  }

  response: HTTP.Response;
  response.code = 200;
  response.body = sprint(PAGE_HTML, sprint(SESSION_HTML, session_id));
  return response;
}

get_session_data :: (request: *HTTP.Request) -> HTTP.Response {
  response: HTTP.Response;
  response.code = 200;
  builder: String_Builder;
  print_to_builder(*builder, "<ul>\n");
  for 0..3 {
    if it == 1 {  // highlight this one
      print_to_builder(*builder, "  <li style=\"font-size: 2em; color: red;\">Thing %</li>\n", it);
    } else {
      print_to_builder(*builder, "  <li style=\"font-size: 2em; color: blue;\">Thing %</li>\n", it);
    }
  }
  print_to_builder(*builder, "</ul>\n");
  response.body = sprint(SESSION_DATA_HTML, builder_to_string(*builder));
  return response;
}

get_rickrolled :: (request: *HTTP.Request) -> HTTP.Response {
  response: HTTP.Response;
  response.code = 200;
  response.body = copy_string(RICKROLL_HTML);
  return response;
}

get_join :: (request: *HTTP.Request) -> HTTP.Response {
  response: HTTP.Response;
  response.code = 200;
  return response;
}

post_join :: (request: *HTTP.Request) -> HTTP.Response {
  response: HTTP.Response;
  response.code = 200;
  return response;
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

parse_url_encoded_form :: (params: string) -> Table(string, string) {
  result: Table(string, string);
  paramset := split(params, "&");
  for paramset {
    found, key, value := split_from_left(it, "=");
    if found {
      key   = HTTP.percent_decode(key);
      value = HTTP.percent_decode(value);
      table_add(*result, key, value);
    } else {
      log_error("Problematic parameter '%'\n", it);
    }
  }
  return result;
}

post_new :: (request: *HTTP.Request) -> HTTP.Response {
  new_session_url := "/session?sessionId=4090";
  headers: [..] HTTP.Header;
  array_add(*headers, .{"HX-Redirect", copy_string(new_session_url)});
  return .{ code=302, headers=headers};
}

post_index :: (request: *HTTP.Request) -> HTTP.Response {
  response: HTTP.Response;
  response.code = 200;
  
  form_params := parse_url_encoded_form(request.body);

  first_name := "";
  last_name := "";
  found := false;
  first_name, found = table_find(*form_params, "first_name");
  last_name, found = table_find(*form_params, "last_name");
  results, success := Postgres.execute(conn, User, tprint("INSERT INTO users (first_name, last_name) VALUES('%', '%');", first_name, last_name));

  templated := render_user_list_only();
  defer free(templated.data);
  response.body = copy_string(templated);
  return response;
}

HTTP :: #import "HTTP";
Postgres :: #import "Postgres";

#import "Hash_Table";
#import "String";
#import "Basic";
#import "Random";