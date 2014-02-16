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

and    $0xfffffffffffffff0,%rsp
and    $0xfffffffffffffff8,%rax
and    $0xff,%rcx
and    $0xff00,%rcx
and    $0xff0000,%rcx
and    %rax,%rcx
and    %rax,%rcx
and    $0x7,%rax
and    $0x50, %rsp

sub    $0x50,%rsp
sub    %rcx,%rax
sub    %rcx,%rax
sub    $0x1,%rax
sub    $0x50,%rsp
sub    $0x10,%rsp

cmp    $0x0,%rax
cmp    %rcx,%rax
cmp    $0x1,%rax
cmp    $0x2,%rax
#cmp    $0xf2,%rax

add    $0x1,%rax
add    $0xfffffffffffffff9, %rsp
add    $0xf9, %rsp
add    $0x2,%rax
add    %rcx,%rax
add    $0x8,%rcx
add    $0x1023291, %rbx
