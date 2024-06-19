main :: () {
  #if OS != .WINDOWS {
    signal(SIGINT, handler);
  }

  iter := 0;
  while true {
    print("iter %\n", iter);
    iter += 1;
    if should_exit {
      print("Exiting gracefully!\n");
      break;
    }
  }
}

#import "Basic";

#scope_file

// Quick and dirty ctrl+C handling on macOS+Linux. 
should_exit := false;

#if OS != .WINDOWS {
  #import "POSIX";
  libc :: #library,system "libc";
  signal :: (signal: int, handler: (s32) -> void #c_call) -> void #foreign libc;
  handler :: (signal: s32) #c_call { 
    if signal == SIGINT  should_exit = true; 
  }
}