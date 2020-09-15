(func $gc_alloc (import "rt" "gc_alloc") (param i32 i32) (result externref))
(func $gc_ref_obj (import "rt" "gc_ref_obj") (param externref i32) (result externref))
(func $gc_set_obj (import "rt" "gc_set_obj") (param externref i32 externref))

(func $invoke (import "rt" "invoke") (param externref))

(func $make_obj (export "make_obj") (result externref)
  (local $obj externref)
  (local.set $obj (call $gc_alloc (i32.const 1) (i32.const 0)))
  (call $gc_set_obj (local.get $obj) (i32.const 0) (ref.null extern))
  (local.get $obj))

(func $attach_callback (export "attach_callback")
      (param $obj externref) (param $callback externref)
  (call $gc_set_obj (local.get $obj) (i32.const 0) (local.get $callback)))

(func $invoke_callback (export "invoke_callback")
      (param $obj externref)
  (call $invoke (call $gc_ref_obj (local.get $obj) (i32.const 0))))
