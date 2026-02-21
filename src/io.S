.section .text
.global outb
.type outb, @function
/* void outb(uint16_t port, uint8_t value) */
outb:
    mov 4(%esp), %dx   /* port */
    mov 8(%esp), %al   /* value */
    out %al, %dx
    ret

.global inb
.type inb, @function
/* uint8_t inb(uint16_t port) */
inb:
    mov 4(%esp), %dx   /* port */
    xor %eax, %eax
    in %dx, %al
    ret

