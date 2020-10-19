	.functype	out_of_memory () -> ()
	.import_module	out_of_memory, rt
	.import_name	out_of_memory, out_of_memory
	.functype	release (i32) -> ()
	.import_module	release, rt
	.import_name	release, release
	.functype	invoke (i32) -> ()
	.import_module	invoke, rt
	.import_name	invoke, invoke

	.functype	malloc (i32) -> (i32)
	.functype	free (i32) -> ()

	.text

make_obj:
	.hidden	make_obj
	.globl	make_obj
	.export_name	make_obj, make_obj
	.no_dead_strip	make_obj
	.type	make_obj,@function
	.functype	make_obj () -> (i32)
	.local  	i32
	block
	i32.const	4
	call	malloc
	local.tee	0
	br_if   	0
	call	out_of_memory
	unreachable
	unreachable
	end_block
	local.get	0
	i32.const	-1
	i32.store	0
	local.get	0
	end_function


free_obj:
	.hidden	free_obj
	.globl	free_obj
	.export_name	free_obj, free_obj
	.no_dead_strip	free_obj
	.type	free_obj,@function
	.functype	free_obj (i32) -> ()
	local.get	0
	i32.load	0
	call	release
	local.get	0
	call	free
	end_function


attach_callback:
	.hidden	attach_callback
	.globl	attach_callback
	.export_name	attach_callback, attach_callback
        .no_dead_strip	attach_callback
	.type	attach_callback,@function
	.functype	attach_callback (i32, i32) -> ()
	local.get	0
	i32.load	0
	call	release
	local.get	0
	local.get	1
	i32.store	0
	end_function

invoke_callback:
	.hidden	invoke_callback
	.globl	invoke_callback
	.export_name	invoke_callback, invoke_callback
	.no_dead_strip	invoke_callback
	.type	invoke_callback,@function
	.functype	invoke_callback (i32) -> ()
	local.get	0
	i32.load	0
	call	invoke
	end_function
