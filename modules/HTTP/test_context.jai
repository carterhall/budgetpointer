#add_context total_allocations: int = 0;

main :: () {
  /*
  new_context := context;
  new_context.allocator = temp;
  push_context new_context {
    print("allocator = %\n", context.default_allocator);

    my_array := NewArray(100, int);
    my_array[3] = 4;
    print("my_array[3] = %\n", my_array[3]);
    reset_temporary_storage();

    my_array[3] = 5;
    print("my_array[3] = %\n", my_array[3]);
  }
  */


  new_context := context;
  new_context.allocator.proc = allocator_that_counts;
  new_context.allocator.data = null;  // Many allocators will need some data. Here we don't, let's just have it be null.
  new_context.print_style.default_format_struct.use_newlines_if_long_form = true;

  push_context new_context {
    print("Total allocations: %\n", context.total_allocations);
    arr := NewArray(32, float);
    print("Total allocations: %\n", context.total_allocations);
    free(arr.data);
  }
}
// inconclusive....

allocator_that_counts :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory_pointer: *void, proc_data: *void) -> *void {
    if mode == .ALLOCATE || mode == .RESIZE  context.total_allocations += 1;

    return context.default_allocator.proc(mode, size, old_size, old_memory_pointer, proc_data);
}

/*
allocator_example :: () {
    new_context := context;  // Copy all values from Context.
    new_context.allocator.proc = my_allocator_proc;
    new_context.allocator.data = null;  // Many allocators will need some data. Here we don't, let's just have it be null.

    /*
    push_context new_context {
        // Let's pretend this thing we are calling is in someone else's module. It could be!
        some_proc_in_someone_elses_module();
    }
    */

    // Once the context is popped, we are back using the old allocator, so
    // we can allocate something of 42 bytes and not get a Hello Sailor:

    final_mem := alloc(42);
    print("final_mem is: %\n", final_mem);
}
*/


#import "Basic";