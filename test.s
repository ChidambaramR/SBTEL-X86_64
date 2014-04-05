mov $0x1, %rbx
mov $0x2, %rax
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
jge l4
jmp l4
l2:
jmp l3
l4:
mov %rax, %rbx
mov $0x10, %rax

