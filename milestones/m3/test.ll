target triple = "wasm32-unknown-unknown"

; Reference types
%extern = type opaque
%externref = type %extern addrspace(10)*

%funcptr = type void () addrspace(20)*
%funcref = type i8 addrspace(20)*

; External functions
declare void @free(i8*) local_unnamed_addr
declare hidden i8* @malloc(i32) local_unnamed_addr
declare void @out_of_memory() local_unnamed_addr #1
declare void @invoke(%externref) local_unnamed_addr #7

; Intrinsics
declare void @llvm.trap()
declare i32 @llvm.wasm.table.grow.externref(i8 addrspace(1)*, %externref, i32) nounwind readonly
declare %externref @llvm.wasm.ref.null.extern() nounwind readonly
declare i32 @llvm.wasm.table.size(i8 addrspace(1)*) nounwind readonly

%struct.freelist = type { i32, %struct.freelist* }
@freelist = hidden local_unnamed_addr global %struct.freelist* null

; Returns the value at the top of the list and frees the head
; Reduces the length of list by one.
; Fails if list is empty.
define i32 @freelist_pop() {
  ; Check if the freelist is null
  %head = load %struct.freelist*, %struct.freelist** @freelist, align 4
  %head_is_null = icmp eq %struct.freelist* %head, null
  br i1 %head_is_null, label %null_head, label %good

  ; fail if it is
null_head:
  unreachable

good:
  ; Load v in order to return it
  %tmp = getelementptr inbounds %struct.freelist, %struct.freelist* %head, i32 0, i32 0
  %v = load i32, i32* %tmp

  ; Load a ptr to the next element
  %nextptr = getelementptr inbounds %struct.freelist, %struct.freelist* %head, i32 0, i32 1
  %next = load %struct.freelist*, %struct.freelist** %nextptr

  ; Store next into freelist
  store %struct.freelist* %next, %struct.freelist** @freelist

  ; Free head and return the value that we loaded from head earlier on
  %headi8 = bitcast %struct.freelist* %head to i8*
  call void @free(i8* nonnull %headi8)
  
  ret i32 %v
}

; Adds an element to the top of the list
; Increases the length of list by one.
define void @freelist_push(i32 %v) {
  ; allocate new node and check that malloc did not return null
  %tmp = call align 16 dereferenceable_or_null(8) i8* @malloc(i32 8)
  %node = bitcast i8* %tmp to i32*
  %is_null = icmp eq i32* %node, null  
  br i1 %is_null, label %oom, label %good

oom:
  call void @out_of_memory()
  unreachable

good:
  ; store v in the new node
  store i32 %v, i32* %node

  ; setup pointers to freelist and node->next
  %freelist = load %struct.freelist*, %struct.freelist** @freelist
  %node_next = getelementptr inbounds i32, i32* %node, i32 1
  %node_next_ptr = bitcast i32* %node_next to %struct.freelist**
  
  ; store freelist in node->next
  store %struct.freelist* %freelist, %struct.freelist** %node_next_ptr
  ; store node into freelist
  store i32* %node, i32** bitcast (%struct.freelist** @freelist to i32**)

  ret void
}

; Linear memory references externref values by putting them into the object
; table, then referring them via index.
@objects = local_unnamed_addr addrspace(1) global [0 x %externref] undef

define void @expand_table() #3 {
  ; get current table size
  %tableptr = getelementptr [0 x %externref], [0 x %externref] addrspace(1)* @objects, i32 0, i32 0
  %tb = bitcast %externref addrspace(1)* %tableptr to i8 addrspace(1)*
  %sz = call i32 @llvm.wasm.table.size(i8 addrspace(1)* %tb)

  ; grow the table by (old_size >> 1) + 1.
  %shf = lshr i32 %sz, 1
  %incsize = add nuw i32 %shf, 1
  %null = call %externref @llvm.wasm.ref.null.extern()
  %ret = call i32 @llvm.wasm.table.grow.externref(i8 addrspace(1)* %tb, %externref %null, i32 %incsize)

  ; if growing the table failed, signal the runtime, then abort
  %failed = icmp eq i32 %ret, -1
  br i1 %failed, label %oom, label %good

oom:
  call void @out_of_memory()
  unreachable

good:
  %newsize = add i32 %sz, %incsize
  br label %loophd

loophd:
  %newi = phi i32 [ %newsize, %good ], [ %i, %loopbody]
  %done = icmp eq i32 %newi, %sz
  br i1 %done, label %end, label %loopbody

end:
  ret void

loopbody:
  %i = add i32 %newi, -1
  call void @freelist_push(i32 %i)
  br label %loophd
}

define i32 @intern(%externref %ref) {
  %head = load %struct.freelist*, %struct.freelist** @freelist, align 4
  %is_null = icmp eq %struct.freelist* %head, null
  br i1 %is_null, label %need_expand, label %do_intern

need_expand:      
  call void @expand_table()
  br label %do_intern

do_intern:
  %handle = call i32 @freelist_pop()
  %p = getelementptr [0 x %externref], [0 x %externref] addrspace(1)* @objects, i32 0, i32 %handle
  store %externref %ref, %externref addrspace(1)* %p
  ret i32 %handle
}

; release the slot in the object table corresponding to the handle
define void @release(i32 %handle) {
  ; if handle is -1 then ignore it
  %is_neg = icmp eq i32 %handle, -1
  br i1 %is_neg, label %end, label %body

body:
  %null = call %externref @llvm.wasm.ref.null.extern()
  %p = getelementptr [0 x %externref], [0 x %externref] addrspace(1)* @objects, i32 0, i32 %handle
  store %externref %null, %externref addrspace(1)* %p
  call void @freelist_push(i32 %handle)
  br label %end

end:
  ret void
}

define %externref @handle_value(i32 %handle) {
  ; if handle is -1 then return null
  %is_neg = icmp eq i32 %handle, -1
  br i1 %is_neg, label %retnull, label %body

retnull:
  %null = call %externref @llvm.wasm.ref.null.extern()
  br label %end

body:
  %p = getelementptr [0 x %externref], [0 x %externref] addrspace(1)* @objects, i32 0, i32 %handle
  %v = load %externref, %externref addrspace(1)* %p
  br label %end

end:
  %retv = phi %externref [%null, %retnull], [%v, %body]
  ret %externref %retv
}

; allocates a new object in linear memory and if 
; that fails it signals the runtime and aborts
define i32* @make_obj() #0 {
  ; allocates a new i32 representing an obj
  %tmp = call dereferenceable_or_null(4) i8* @malloc(i32 4) 
  %ptr = bitcast i8* %tmp to i32*
  %is_null = icmp eq i32* %ptr, null
  br i1 %is_null, label %oom, label %body

oom:
  call void @out_of_memory()
  unreachable

body:
  ; initialize callback handle -1 (invalid) for a fresh object
  store i32 -1, i32* %ptr
  ret i32* %ptr
}

define void @free_obj(i32* %obj) #8 {
  %v = load i32, i32* %obj
  call void @release(i32 %v)
  %ptr = bitcast i32* %obj to i8*
  call void @free(i8* %ptr)
  ret void
}

define void @attach_callback(i32* %obj, %externref %callback) #2 {
  ; release old handle
  %oldhandle = load i32, i32* %obj
  call void @release(i32 %oldhandle)
  ; intern the new callback, and store handle to object
  %handle = call i32 @intern(%externref %callback)
  store i32 %handle, i32* %obj
  ret void
}

define void @invoke_callback(i32* %obj) #6 {
  %handle = load i32, i32* %obj
  %v = call %externref @handle_value(i32 %handle)
  call void @invoke(%externref %v)
  ret void
}

attributes #0 = { "wasm-export-name"="make_obj" }
attributes #8 = { "wasm-export-name"="free_obj" }
attributes #1 = { noreturn "wasm-import-module"="rt" "wasm-import-name"="out_of_memory" }
attributes #2 = { "wasm-export-name"="attach_callback" }
attributes #3 = { "wasm-export-name"="expand_table" }
attributes #6 = { "wasm-export-name"="invoke_callback" }
attributes #7 = { "wasm-import-module"="rt" "wasm-import-name"="invoke" }
