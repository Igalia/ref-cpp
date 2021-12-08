; Reference types
%extern = type opaque
%externref = type %extern addrspace(10)*

%funcptr = type void () addrspace(20)*
%funcref = type i8 addrspace(20)*

; External functions
declare void @free(i8*) local_unnamed_addr
declare i8* @malloc(i32) local_unnamed_addr
declare void @out_of_memory() local_unnamed_addr
declare void @invoke(%externref) local_unnamed_addr
; Intrinsics
declare void @llvm.trap()
declare i32 @llvm.wasm.table.grow.externref(i8 addrspace(1)*, %externref, i32) nounwind readonly
declare %externref @llvm.wasm.ref.null.extern() nounwind readonly
declare i32 @llvm.wasm.table.size(i8 addrspace(1)*) nounwind readonly

%struct.freelist = type { i32, %struct.freelist* }
@freelist = hidden local_unnamed_addr global %struct.freelist* null, align 4

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
  tail call void @free(i8* nonnull %headi8)
  ret i32 %v
}

; Adds an element to the top of the list
; Increases the length of list by one.
define void @freelist_push(i32 %v) {
  ; allocate new node and check that malloc did not return null
  %nodeptr = tail call i8* @malloc(i32 4)
  %is_null = icmp eq i8* %nodeptr, null  
  br i1 %is_null, label %oom, label %good

oom:
  tail call void @out_of_memory()
  unreachable

good:
  ; cast and store v in the new node
  %node = bitcast i8* %nodeptr to i32*
  store i32 %v, i32* %node, align 4

  ; setup pointers to freelist and node->next
  %freelist = load %struct.freelist*, %struct.freelist** @freelist, align 4
  %node_next = getelementptr inbounds i32, i32* %node, i32 4
  %node_next_ptr = bitcast i32* %node_next to %struct.freelist**
  
  ; store freelist in node->next
  store %struct.freelist* %freelist, %struct.freelist** %node_next_ptr, align 4
  ; store node into freelist
  store i32* %node, i32** bitcast (%struct.freelist** @freelist to i32**), align 4
  ret void
}

; Linear memory references externref values by putting them into the object
; table, then referring them via index.
@objects = local_unnamed_addr addrspace(1) global [0 x %externref] undef

define void @expand_table() {
  ; get current table size
  %tableptr = getelementptr [0 x %externref], [0 x %externref] addrspace(1)* @objects, i32 0, i32 0
  %tb = bitcast %externref addrspace(1)* %tableptr to i8 addrspace(1)*
  %sz = call i32 @llvm.wasm.table.size(i8 addrspace(1)* %tb)
  
  ; grow the table by (old_size >> 1) + 1.
  %shf = lshr i32 %sz, 2
  %incsize = add nuw i32 %shf, 1
  %null = call %externref @llvm.wasm.ref.null.extern()
  %newsize = tail call i32 @llvm.wasm.table.grow.externref(i8 addrspace(1)* %tb, %externref %null, i32 %incsize)
  
  ; if growing the table failed, signal the runtime, then abort
  %failed = icmp eq i32 %newsize, -1
  br i1 %failed, label %oom, label %good

oom:
  tail call void @out_of_memory()
  unreachable

good:
  ; push freelist entries for new slots
  %starti = sub nsw i32 %newsize, 1
  %canstart = icmp ult i32 %starti, %sz
  br i1 %canstart, label %end, label %loop

loop:
  %phires = phi i32 [ %i, %loop ], [ %starti, %good]
  call void @freelist_push(i32 %phires)
  %i = sub nuw i32 %phires, 1
  %done = icmp ult i32 %i, %sz
  br i1 %done, label %end, label %loop

end:
  ret void
}

define i32 @intern(%externref %ref) {
  %head = load %struct.freelist*, %struct.freelist** @freelist, align 4
  %is_null = icmp eq %struct.freelist* %head, null
  br i1 %is_null, label %need_expand, label %do_intern

need_expand:
  tail call void @expand_table()
  br label %do_intern

do_intern:
  %handle = tail call i32 @freelist_pop()
  %p = getelementptr [0 x %externref], [0 x %externref] addrspace(1)* @objects, i32 0, i32 %handle
  store %externref %ref, %externref addrspace(1)* %p
  ret i32 %handle
}

; release the slow in the object table corresponding to the handle `id`
define void @release(i32 %handle) {
  ; if handle is -1 then ignore it
  %is_neg = icmp eq i32 %handle, -1
  br i1 %is_neg, label %end, label %body

body:
  %null = call %externref @llvm.wasm.ref.null.extern()
  %p = getelementptr [0 x %externref], [0 x %externref] addrspace(1)* @objects, i32 0, i32 %handle
  store %externref %null, %externref addrspace(1)* %p
  tail call void @freelist_push(i32 %handle)
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
define i32* @make_obj() {
  %ptr = call i8* @malloc(i32 4)
  %is_null = icmp eq i8* %ptr, null
  br i1 %is_null, label %oom, label %body

oom:
  tail call void @out_of_memory()
  unreachable

body:
  ; initialize callback handle -1 (invalid) for a fresh object
  %ptr32 = bitcast i8* %ptr to i32*
  store i32 -1, i32* %ptr32
  ret i32* %ptr32
}

define void @free_obj(i32* %obj) {
  %v = load i32, i32* %obj
  call void @release(i32 %v)
  %ptr = bitcast i32* %obj to i8*
  call void @free(i8* %ptr)
  ret void
}

define void @attach_callback(i32* %obj, %externref %callback) {
  ; release old handle
  %oldhandle = load i32, i32* %obj
  call void @release(i32 %oldhandle)
  ; intern the new callback, and store handle to object
  %handle = call i32 @intern(%externref %callback)
  store i32 %handle, i32* %obj
  ret void
}

define void @invoke_callback(i32* %obj) {
  %handle = load i32, i32* %obj
  %v = call %externref @handle_value(i32 %handle)
  call void @invoke(%externref %v)
  ret void
}
