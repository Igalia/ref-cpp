        .functype       out_of_memory () -> ()
        .import_module  out_of_memory, rt
        .import_name    out_of_memory, out_of_memory
        .functype       invoke (externref) -> ()
        .import_module  invoke, rt
        .import_name    invoke, invoke

        .functype       malloc (i32) -> (i32)
        .functype       free (i32) -> ()

        .text

freelist:
        # struct freelist { uint32_t handle; struct freelist *next; };
        .globaltype freelist, i32

## Pop a handle off the freelist.  Precondition: freelist non-empty.
freelist_pop:
        .hidden freelist_pop
        .globl freelist_pop
        .type freelist_pop,@function
        .functype       freelist_pop () -> (i32)
        # Abort if the freelist is empty.
        global.get freelist
        i32.eqz
        if
        unreachable
        end_if
        # Return value is the handle from the head of the freelist.
        global.get freelist
        i32.load 0
        # Push old freelist head.
        global.get freelist
        # Set $freelist to the old head's "next" link.
        global.get freelist
        i32.load 4
        global.set freelist
        # Free the old head; the handle return value remains on the stack.
        call free
        end_function

## Push a handle onto the freelist.  May call out_of_memory.
freelist_push:
        .hidden freelist_push
        .globl freelist_push
        .type freelist_push,@function
        .functype freelist_push (i32) -> ()
        .local i32              # new_head
        # Allocate a new head.
        i32.const 8
        call malloc
        local.tee 1
        
        # If the malloc failed, signal the runtime, then abort.
        i32.eqz
        if
        call out_of_memory
        unreachable
        end_if

        # Link new freelist head to old freelist.
        local.get 1
        global.get freelist
        i32.store 4

        # Initialize handle for new freelist head.
        local.get 1
        local.get 0
        i32.store 0

        # Set new head as $freelist.
        local.get 1
        global.set freelist
        end_function

# Linear memory references externref values by putting them into the
# object table, then referring to them via index.  We use the word
# "handle" to refer to an externref's index into the object table.
objects:
        .tabletype objects,externref
        
# When we need to intern a new externref into the object table, we get
# the handle by popping it off a freelist.  Every free slot in the
# table is on the freelist.  If the freelist is empty, then first we
# expand the table, pushing new handles for each new slot onto the free
# list.
expand_table:
        .hidden expand_table
        .globl expand_table
        .type expand_table,@function
        .functype expand_table () -> ()
        .local i32,i32          # old_size, end
        table.size objects
        local.set 0
        # Grow the table by (old_size >> 1) + 1.
        ref.null_extern
        local.get 0
        i32.const 1
        i32.shr_u
        i32.const 1
	i32.add
        table.grow objects
        # If growing the table failed, signal the runtime, then abort.
        i32.const -1
        i32.eq
        if
        call out_of_memory
        unreachable
        end_if
        # Push freelist entries for new slots.
        table.size objects
        local.set 1
        loop
        local.get 1
        local.get 0
        i32.eq
        if
        return
        end_if
        local.get 1
        i32.const 1
        i32.sub
        local.set 1
        local.get 1
        call freelist_push
        br 0
	end_loop
        end_function

## Put $obj into the object table, returning a fresh handle.
intern:
        .hidden intern
        .globl intern
        .type intern,@function
        .functype intern (externref) -> (i32)
        .local i32              # handle
        global.get freelist
        i32.eqz
        if
        call expand_table
        end_if
        call freelist_pop
        local.set 1
        local.get 1
        local.get 0
        table.set objects
        local.get 1
        end_function

## Release the slot in the object table corresponding to $handle.
release:
        .hidden release
        .globl release
        .type release,@function
        .functype       release (i32) -> ()
        # If $handle was -1 (invalid), just ignore it.
        local.get 0
        i32.const -1
        i32.eq
        if
        return
        end_if
        local.get 0
        ref.null_extern
        table.set objects
        local.get 0
        call freelist_push
        end_function

handle_value:
        .hidden handle_value
        .globl handle_value
        .type handle_value,@function
        .functype       handle_value (i32) -> (externref)
        local.get 0
        i32.const -1
        i32.eq
        if externref
        ref.null_extern
        else
        local.get 0
        table.get objects
        end_if
        end_function

make_obj:
        .hidden make_obj
        .globl  make_obj
        .export_name    make_obj, make_obj
        .no_dead_strip  make_obj
        .type   make_obj,@function
        .functype       make_obj () -> (i32)
        .local          i32     # obj
        # Allocate a new object in linear memory.  If that fails,
        # signal the runtime, and then abort.
        i32.const       4
        call    malloc
        i32.eqz
        if
        call    out_of_memory
        unreachable
        end_if
        # Initialize callback handle -1 (invalid) for fresh object.
        local.get       0
        i32.const       -1
        i32.store       0
        local.get       0
        end_function


free_obj:
        .hidden free_obj
        .globl  free_obj
        .export_name    free_obj, free_obj
        .no_dead_strip  free_obj
        .type   free_obj,@function
        .functype       free_obj (i32) -> ()
        # Release the callback handle.
        local.get       0
        i32.load        0
        call release
        local.get       0
        call free
        end_function


attach_callback:
        .hidden attach_callback
        .globl  attach_callback
        .export_name    attach_callback, attach_callback
        .no_dead_strip  attach_callback
        .type   attach_callback,@function
        .functype       attach_callback (i32, externref) -> ()
        # Release old handle.
        local.get       0
        i32.load        0
        call release
        # Intern the new callback, and store handle to object.
        local.get       0
        local.get       1
        call intern
        i32.store       0
        end_function

invoke_callback:
        .hidden invoke_callback
        .globl  invoke_callback
        .export_name    invoke_callback, invoke_callback
        .no_dead_strip  invoke_callback
        .type   invoke_callback,@function
        .functype       invoke_callback (i32) -> ()
        local.get       0
        i32.load        0
        call handle_value
        call invoke
        end_function
