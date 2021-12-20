target triple = "wasm32-unknown-unknown"

; Reference types
%extern = type opaque
%externref = type %extern addrspace(10)*

%funcptr = type void () addrspace(20)*
%funcref = type i8 addrspace(20)*

; intrinsic decl
declare %externref @llvm.wasm.ref.null.extern() nounwind readonly

; External functions
declare %externref @gc_alloc(i32, i32) local_unnamed_addr #0
declare %externref @gc_ref_obj(%externref, i32) local_unnamed_addr #1
declare void @gc_set_obj(%externref, i32, %externref) local_unnamed_addr #2
declare void @invoke(%externref) local_unnamed_addr #3

define %externref @make_obj() #4 {
  %obj = call %externref @gc_alloc(i32 1, i32 0)
  %null = call %externref @llvm.wasm.ref.null.extern()
  call void @gc_set_obj(%externref %obj, i32 0, %externref %null)
  ret %externref %obj
}

define void @attach_callback(%externref %obj, %externref %callback) #5 {
  call void @gc_set_obj(%externref %obj, i32 0, %externref %callback)
  ret void
}

define void @invoke_callback(%externref %obj) #6 {
  %ref = call %externref @gc_ref_obj(%externref %obj, i32 0)
  call void @invoke(%externref %ref)
  ret void
}

attributes #0 = { "wasm-import-module"="rt" "wasm-import-name"="gc_alloc" }
attributes #1 = { "wasm-import-module"="rt" "wasm-import-name"="gc_ref_obj" }
attributes #2 = { "wasm-import-module"="rt" "wasm-import-name"="gc_set_obj" }
attributes #3 = { "wasm-import-module"="rt" "wasm-import-name"="invoke" }

attributes #4 = { "wasm-export-name"="make_obj" }
attributes #5 = { "wasm-export-name"="attach_callback" }
attributes #6 = { "wasm-export-name"="invoke_callback" }
