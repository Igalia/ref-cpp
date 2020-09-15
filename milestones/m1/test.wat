(module
  (type (;0;) (func (result i32)))
  (type (;1;) (func (param i32) (result i32)))
  (type (;2;) (func (param i32)))
  (type (;3;) (func (param i32 i32)))
  (import "env" "__linear_memory" (memory (;0;) 0))
  (import "env" "__indirect_function_table" (table (;0;) 0 funcref))
  (import "env" "malloc" (func (;0;) (type 1)))
  (import "c2js" "release" (func $release (type 2)))
  (import "env" "free" (func (;2;) (type 2)))
  (func $make_obj (type 0) (result i32)
    (local i32)
    i32.const 4
    call 0
    local.tee 0
    i32.const -1
    i32.store
    local.get 0)
  (func $free_obj (type 2) (param i32)
    (local i32)
    block  ;; label = @1
      local.get 0
      i32.load
      local.tee 1
      i32.const -1
      i32.eq
      br_if 0 (;@1;)
      local.get 1
      call $release
    end
    local.get 0
    call 2)
  (func $install_callback (type 3) (param i32 i32)
    block  ;; label = @1
      local.get 1
      i32.const -1
      i32.ne
      br_if 0 (;@1;)
      unreachable
      unreachable
    end
    local.get 0
    local.get 1
    i32.store)
  (export "make_obj" (func $make_obj))
  (export "free_obj" (func $free_obj))
  (export "install_callback" (func $install_callback)))
