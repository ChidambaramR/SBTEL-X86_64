mov    %rsp, %rbp
mov    %rdi, 0x1234(%rbp)
mov    %rdi,0xfffffffffffffff8(%rbp)
mov    %rsi,0xfffffffffffffff0(%rbp)
mov    %rax,0xffffffffffffffe8(%rbp)
mov    0xfffffffffffffff0(%rbp),%rax
mov    0xfffffffffffffff0(%rbp),%rcx
mov    %rax,%rsi
mov    $0x0,%rax
mov    %rax,0xffffffffffffffc0(%rbp)
mov    %rax,%rdi
