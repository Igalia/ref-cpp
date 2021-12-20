        .functype       gc_alloc (i32, i32) -> (externref)
        .import_module  gc_alloc, rt
        .import_name    gc_alloc, gc_alloc

        .functype       gc_ref_obj (externref, i32) -> (externref)
        .import_module  gc_ref_obj, rt
        .import_name    gc_ref_obj, gc_ref_obj

        .functype       gc_set_obj (externref, i32, externref) -> ()
        .import_module  gc_set_obj, rt
        .import_name    gc_set_obj, gc_set_obj

        .functype       invoke (externref) -> ()
        .import_module  invoke, rt
        .import_name    invoke, invoke

make_obj:
        .hidden make_obj
        .globl  make_obj
        .export_name    make_obj, make_obj
        .no_dead_strip  make_obj
        .type   make_obj,@function
        .functype       make_obj () -> (externref)
        .local          externref     # obj
        # Allocate a new object in managed memory.
        i32.const       1 # nobjs
        i32.const       0 # nbytes
        call    gc_alloc
	local.set 0
	
	# Initialize callback field.
	local.get 0
        i32.const 0
	ref.null_extern
	call gc_set_obj

        local.get       0
        end_function

attach_callback:
        .hidden attach_callback
        .globl  attach_callback
        .export_name    attach_callback, attach_callback
        .no_dead_strip  attach_callback
        .type   attach_callback,@function
        .functype       attach_callback (externref, externref) -> ()
        # Set callback field.
	local.get 0
        i32.const 0
	local.get 1
	call gc_set_obj
        end_function

invoke_callback:
        .hidden invoke_callback
        .globl  invoke_callback
        .export_name    invoke_callback, invoke_callback
        .no_dead_strip  invoke_callback
        .type   invoke_callback,@function
        .functype       invoke_callback (externref) -> ()
        local.get       0
        i32.const 0
	call gc_ref_obj
        call invoke
        end_function
