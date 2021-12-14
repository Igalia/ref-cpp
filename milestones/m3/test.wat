(memory $mem (import "env" "__linear_memory") 0)
(func $malloc (import "env" "malloc") (param i32) (result i32))
(func $free (import "env" "free") (param i32))

(func $invoke (import "rt" "invoke") (param externref))
(func $out_of_memory (import "rt" "out_of_memory"))

;; struct freelist { uint32_t handle; struct freelist *next; };
(global $freelist (mut i32) (i32.const 0))

;; Pop a handle off the freelist.  Precondition: freelist non-empty.
(func $freelist_pop (result i32)
  ;; Abort if the freelist is empty.
  (if (i32.eqz (global.get $freelist)) (then (unreachable)))

  ;; Return value is the handle from the head of the freelist.
  (i32.load offset=0 (global.get $freelist))

  ;; Push old freelist head.
  (global.get $freelist)

  ;; Set $freelist to the old head's "next" link.
  (global.set $freelist (i32.load offset=4 (global.get $freelist)))

  ;; Free the old head; the handle return value remains on the stack.
  (call $free))

;; Push a handle onto the freelist.  May call out_of_memory.
(func $freelist_push (param $idx i32)
  (local $new_head i32)

  ;; Allocate a new head.
  (local.tee $new_head (call $malloc (i32.const 8)))

  ;; If the malloc failed, signal the runtime, then abort.
  (if (i32.eqz) (then (call $out_of_memory) (unreachable)))

  ;; Link new freelist head to old freelist.
  (i32.store offset=4 (local.get $new_head) (global.get $freelist))

  ;; Initialize handle for new freelist head.
  (i32.store offset=0 (local.get $new_head) (local.get $idx))

  ;; Set new head as $freelist.
  (global.set $freelist (local.get $new_head)))

;; Linear memory references externref values by putting them into the
;; object table, then referring to them via index.  We use the word
;; "handle" to refer to an externref's index into the object table.
(table $objects 0 externref)

;; When we need to intern a new externref into the object table, we get
;; the handle by popping it off a freelist.  Every free slot in the
;; table is on the freelist.  If the freelist is empty, then first we
;; expand the table, pushing new handles for each new slot onto the free
;; list.
(func $expand_table
  (local $old_size i32)
  (local $end i32)
  (local.set $old_size (table.size $objects))

  ;; Grow the table by (old_size >> 1) + 1.
  (table.grow $objects
              (ref.null extern)
              (i32.add (i32.shr_u (local.get $old_size)
                                  (i32.const 1))
                       (i32.const 1)))

  ;; If growing the table failed, signal the runtime, then abort.
  (if (i32.eq (i32.const -1))
      (then (call $out_of_memory) (unreachable)))

  ;; Push freelist entries for new slots.
  (local.set $end (table.size $objects))
  (loop $loop
    (if (i32.eq (local.get $end) (local.get $old_size))
        (then (return)))
    (local.set $end (i32.sub (local.get $end) (i32.const 1)))
    (call $freelist_push (local.get $end))
    (br $loop)))

;; Put $obj into the object table, returning a fresh handle.
(func $intern (param $obj externref) (result i32)
  (local $handle i32)

  ;; Expand the table if no slots are free.
  (if (i32.eqz (global.get $freelist))
      (then (call $expand_table)))

  ;; Store $obj into the object table and return its handle.
  (local.set $handle (call $freelist_pop))
  (table.set $objects (local.get $handle) (local.get $obj))
  (local.get $handle))

;; Release the slot in the object table corresponding to $handle.
(func $release (param $handle i32)
  ;; If $handle was -1 (invalid), just ignore it.
  (if (i32.eq (local.get $handle) (i32.const -1))
      (then (return)))
  (table.set $objects (local.get $handle) (ref.null extern))
  (call $freelist_push (local.get $handle)))

(func $handle_value (param $handle i32) (result externref)
  (if (result externref)
      (i32.eq (local.get $handle) (i32.const -1))
      (then (ref.null extern))
      (else (table.get $objects (local.get $handle)))))

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
      (param $obj i32) (param $callback externref)
  ;; Release old handle.
  (call $release (i32.load offset=0 (local.get $obj)))

  ;; Intern the new callback, and store handle to object.
  (i32.store offset=0
             (local.get $obj)
             (call $intern (local.get $callback))))

(func $invoke_callback (export "invoke_callback")
      (param $obj i32)
  (call $invoke (call $handle_value (i32.load offset=0 (local.get $obj)))))
