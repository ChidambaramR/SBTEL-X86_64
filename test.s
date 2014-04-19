mov $0x1, %rbx
mov $0x7FFFF6, %rax
#movq %rbx, 0x100(%rax)
movq 0x100(%rax), %rbx
imul %rax
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

