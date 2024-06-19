#run {
  set_build_options_dc(.{do_output = false});

  w := compiler_create_workspace();
  options := get_build_options();
  options.output_type = .EXECUTABLE;
  options.output_executable_name = "server";

	if OS == .MACOS {
    // This uses Postgres.app, which was the best universal-binary option when I wrote this: https://postgresapp.com/
    // However, now, Jai supports arm64, so you should be able to use the homebrew arm64-only version.
    // You'll need to modify this path if you do.
    POSTGRES_APP_LIB_PATH := "/Applications/Postgres.app/Contents/Versions/latest/lib";
    options.additional_linker_arguments = .["-L", POSTGRES_APP_LIB_PATH];
    compiler_add_library_search_directory(POSTGRES_APP_LIB_PATH);
  }

  set_build_options(options, w);

  add_build_file("main.jai", w);
}

#import "Compiler";
#import "Basic";
