mov $0x1, %rbx
mov $0x7FFFE0, %rax
movq %rbx, 0x100(%rax)
mov $0x7FFFE7, %rax
movq 0x100(%rax), %rbx
imul %rax
callq *%rdi
sub $0x1, %rsp
l1:
imul %rax
imul %rbx
jmp l2 
imul %rax
imul %rax
l3:
imul %rax
imul %rax
mov $0x1231, %rcx
cmp $0x1230, %rcx
je l4
jmp l4
l2:
jmp l3
l4:
mov %rax, %rbx
mov $0x10, %rax

