// This is somewhat based on public-domain jai-simplehttp: https://github.com/smari/jai-simplehttp
// The main differences (so far) are
// - multithreading via Thread_Group
// - experimental pure reliance on the temporary allocator within a given request-response cycle

#module_parameters(HANDLE_CTRL_C := true, DEVELOPMENT_BUILD := true);

Verb :: enum_flags { GET; POST; PUT; DELETE; PATCH; TRACE; OPTIONS; CONNECT; HEAD; UNKNOWN_VERB; }

Key_Value :: struct { key: string; value: string; }
Header :: #type,distinct Key_Value;

Request :: struct {
  verb: Verb;
  uri:  string;
  protocol: string;
  headers: [] Header;
  url_params: Table(string, string);
  body: string;
}

Response :: struct {
  code: int;
  headers: [] Header;
  body: string;
}

Route_Handler :: #type (request: *Request) -> Response;

Route :: struct {
  uri: string;
  verb: Verb;
  handler: Route_Handler;
}

// I don't like this being global, but we need the interrupt handler to be able to close the socket
// if we want to cleanly exit on Ctrl+C. Is there another way to do it?
listen_socket: s32;

Server :: struct {
  host := "127.0.0.1";
  port := cast(u16) 8080;

  threads := Thread_Group.{ logging=false, name="Tempo" };
  socket: s32;

  routes: [..] Route;
}

add_route :: (server: *Server, verb: Verb, uri: string, handler: Route_Handler) {
  array_add(*server.routes, Route.{ verb=verb, uri=uri, handler=handler });
}

http_get_status_text :: (status: int) -> string {
  // TODO: This is a partial list.
  if status == {
    case 200; return "OK";
    case 400; return "Bad Request";
    case 401; return "Unauthorized";
    case 403; return "Forbidden";
    case 404; return "Not Found";
    case 418; return "I'm a teapot";
    case 500; return "Internal server error";
    case; return "Confused";
  }
}

http_text_to_verb :: (verb: string) -> Verb {
  if verb == {
    case "GET";     return .GET;
    case "POST";    return .POST;
    case "PUT";     return .PUT;
    case "DELETE";  return .DELETE;
    case "PATCH";   return .PATCH;
    case "TRACE";   return .TRACE;
    case "OPTIONS"; return .OPTIONS;
    case "CONNECT"; return .CONNECT;
    case "HEAD";    return .HEAD;
    case;           return .UNKNOWN_VERB;
  }
}

percent_encode :: (input: string, x_www_form_urlencoded := false) -> string {
  builder: String_Builder;

  for i: 0..input.count-1 {
    c := input[i];
    if (c >= #char "A" && c <= #char "Z") || (c >= #char "a" && c <= #char "z") || c == #char "~" || c == #char "." || c == #char "_" || c == #char "-" {
      append(*builder, c);
    } else if (c == #char " ") && x_www_form_urlencoded {  // TODO also something about newlines?
      append(*builder, "+");
    } else {
      print_to_builder(*builder, "%%%", formatInt(c, base=16, minimum_digits=2));
    }
  }

  return builder_to_string(*builder);
}

percent_decode :: (input: string, x_www_form_urlencoded := false) -> string {  
  builder: String_Builder;
  
  last_percent_index := -3;
  for i: 0..input.count-1 {
    c := input[i];

    if i - last_percent_index > 2 {
      if c == #char "%" {  
        last_percent_index = i;
      } else if c == #char "+" && x_www_form_urlencoded {
        append(*builder, " ");
      } else {
        append(*builder, c);
      }
    } else if i - last_percent_index == 2 {
      char := string_to_int(slice(input, i-1, 2), base=16, T=u8);
      append(*builder, string.{ data=(*char), count=1 });
    }
  }

  return builder_to_string(*builder);
}

run_server :: (server: *Server, num_threads := cast(s32)0) {
  if num_threads == 0 {
    num_threads = get_number_of_processors(); 
    #if OS == .WINDOWS || OS == .LINUX {
      num_threads /= 2;   // Hyperthreads will be reported as individual processors, apparently 
    }
  }

  #if OS != .WINDOWS && HANDLE_CTRL_C {
    signal(SIGINT, signal_handler);  // Handle Ctrl+C so we can cleanup threads
  }

  if !start_listening(server) return;

  init(*server.threads, num_threads, thread_proc); 
  start(*server.threads);
  defer shutdown(*server.threads);

  request_number := 0;
  while !should_exit {
    socket, address := accept(listen_socket);  // Accept client (singlethreaded)

    // Once we have the request socket, pass it off to a worker thread
    work := Thread_Work.{ server=server, socket=socket };
    add_work(*server.threads, *work, tprint("Request #%", request_number));
    request_number += 1;
  }

  print("\nTempo received CTRL+C, shutting down cleanly.\n");
}

start_listening :: (server: *Server) -> success: bool {
  listen_socket = socket(AF_INET, .SOCK_STREAM, 0);
  if listen_socket < 0{
    print("Error: socket value % is less than 0\n", listen_socket); 
    return false;
  }

  optval : u32 = 1;
  if setsockopt(listen_socket, SOL_SOCKET, SO_REUSEADDR, *optval, 4) < 0 {
    print("Error: setsockopt failure\n"); 
    return false;
  }

  if bind(listen_socket, server.host, server.port) < 0 {
    err := get_last_socket_error();
    print("Error: bind returned error %\n", err);
    return false;
  }

  if listen(listen_socket, 5) < 0 {
    print("Error: listen returned negative value\n");
    return false;
  }

  print("Tempo listening on http://%:%\n", server.host, server.port);
  return true;
}


#scope_module

Thread_Work :: struct {
  server: *Server;
  socket:  s32;
}

BUFFER_SIZE :: 1024;
REQUEST_MAX_SIZE :: 1024*1024*64;  // 64 Megabyte body!?

handle_request :: (server: *Server, socket: s32) {
  start_time := current_time_monotonic();

  request_buf: [BUFFER_SIZE+1] u8;  // Stack buffer to receive data
  builder: String_Builder;

  while !should_exit {
    received_bytes := recv(socket, *request_buf, BUFFER_SIZE, 0);

    if received_bytes < 0 && errno() == 9 {
      print("Bad socket file descriptor\n");
      return;
    }
    if request_buf[0] == 0 {
      print("Spurious request\n");
      return;
    }

    if received_bytes < 0 || received_bytes > BUFFER_SIZE || request_buf[0] == 0 {
      print("recv error: received_bytes = %, buf[0] = %, errno = %\n", received_bytes, request_buf[0], errno());
      return;
    }

    append(*builder, string.{ data=request_buf.data, count=received_bytes });

    if received_bytes != BUFFER_SIZE break;
    if builder_string_length(*builder) > REQUEST_MAX_SIZE {
      print("request too big\n");
    }
  }

  request_body := builder_to_string(*builder);

  found, header_text, body := split_from_left(request_body, "\r\n\r\n");
  request: Request;
  request.body = body;
  headers_split := split(header_text, "\r\n");

  headers: [..] Header;
  for headers_split {
    if it_index == 0 { // Request info line
      request_info := split(it, " ");
      if request_info.count < 3  break; // no more data 

      split_url := split(request_info[1], "?");
      request.uri = split_url[0];

      // Cut off trailing slash if present
      if request.uri.count > 1 && request.uri[request.uri.count-1] == #char "/"  request.uri.count -= 1;

      if split_url.count >= 2 {
        url_params_string := split_url[1];
        url_params_split := split(url_params_string, "&");

        for url_param_string: url_params_split {
          if url_param_string.count > 1 {
            url_param_split := split(url_param_string, "=");
            key := percent_decode(url_param_split[0]); 
            value := percent_decode(url_param_split[1]);
            table_add(*request.url_params, key, value);
          }
        }

        print("Table after adding params: %\n", request.url_params);
      }

      request.verb = http_text_to_verb(request_info[0]);
      request.protocol = request_info[2];
    } else {
      found, key, value := split_from_left(it, ":");
      array_add(*headers, .{ key=key, value=value });
    }
  }
  request.headers = headers;


  response := Response.{ code=404, body="Not Found" };
  for route: server.routes {
    if route.uri == request.uri && route.verb == request.verb {
      response = route.handler(*request);
    }
  }

  // Write our response to the socket
  write(socket, "HTTP/1.0 % %\r\n", response.code, http_get_status_text(response.code));
  for h: response.headers  write(socket, "%: %\r\n", h.key, h.value);
  write(socket, "\r\n");
  write(socket, response.body);

  close_and_reset(*socket);

  time_elapsed_us := to_microseconds(current_time_monotonic() - start_time);
  if !should_exit {
    print("[%] % % (% us, thread %)\n", response.code, request.verb, request.uri, time_elapsed_us, context.thread_index);
  }
}

thread_proc :: (group: *Thread_Group, thread: *Thread, work: *void) -> Thread_Continue_Status {
  thread_work := cast(*Thread_Work) work;

  new_context := context;
  new_context.print_style.default_format_struct.use_newlines_if_long_form = true;
  new_context.allocator = temp;

  push_context new_context {
    handle_request(thread_work.server, thread_work.socket);
  }

  reset_temporary_storage();
  return .CONTINUE;
}

//#import "Basic"()(MEMORY_DEBUGGER=DEVELOPMENT_BUILD);
#import "Basic";
#import "Socket";
#import "Thread";
#import "System";
#import "String";
#import "Hash_Table";
//#import "uniform";  // regex, third party

#scope_file

should_exit := false;

// Quick and dirty ctrl+C handling on macOS+Linux.
// The simplest thing seems to be closing the socket directly in the handler.
// Otherwise we'll be left with an accept()/recv() blocking after program exit.
#if HANDLE_CTRL_C && OS != .WINDOWS {
  #import "POSIX";
  libc :: #library,system "libc";
  signal :: (signal: int, handler: (s32) -> void #c_call) -> void #foreign libc;

  signal_handler :: (signal: s32) #c_call { 
    if signal == SIGINT {
      should_exit = true; 
      close(listen_socket);
    }
  }
}

// copied from simple http, can probably eliminate these
write :: inline (fd: s32, msg: string) -> s64 {
  return send(fd, cast(*void) msg.data, xx msg.count, 0);
}

write :: inline (fd: s32, buf: string, args: ..Any) -> s64 {
  tmp := tprint(buf, ..args);
  return send(fd, tmp.data, xx tmp.count, 0);
}