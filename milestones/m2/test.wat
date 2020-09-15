(memory $mem (import "env" "__linear_memory") 0)
(func $malloc (import "env" "malloc") (param i32) (result i32))
(func $free (import "env" "free") (param i32))

(func $release (import "rt" "release") (param i32))
(func $invoke (import "rt" "invoke") (param i32))
(func $out_of_memory (import "rt" "out_of_memory"))

(func $make_obj (export "make_obj") (result i32)
  (local $obj i32)

  ;; Allocate a new object in linear memory.  If that fails, signal the
  ;; runtime, and then abort.
  (if (i32.eqz (local.tee $obj (call $malloc (i32.const 4))))
      (then (call $out_of_memory) (unreachable)))

  ;; Initialize callback handle -1 (invalid) for fresh object.
  (i32.store offset=0 (local.get $obj) (i32.const -1))

  (local.get $obj))

(func $free_obj (export "free_obj") (param $obj i32)
  ;; Release the callback handle.
  (call $release (i32.load offset=0 (local.get $obj)))
  (call $free (local.get $obj)))

(func $attach_callback (export "attach_callback")
      (param $obj i32) (param $callback_handle i32)
  ;; Release old handle.
  (call $release (i32.load offset=0 (local.get $obj)))

  ;; Store handle to object.
  (i32.store offset=0
             (local.get $obj)
             (local.get $callback_handle)))

(func $invoke_callback (export "invoke_callback")
      (param $obj i32)
  (call $invoke (i32.load offset=0 (local.get $obj))))
