#define move_to_user_mode() \
__asm__ ("movl %%esp,%%eax\n\t" \
	"pushl $0x17\n\t" \
	"pushl %%eax\n\t" \
	"pushfl\n\t" \
	"pushl $0x0f\n\t" \
	"pushl $1f\n\t" \
	"iret\n" \
	"1:\tmovl $0x17,%%eax\n\t" \
	"movw %%ax,%%ds\n\t" \
	"movw %%ax,%%es\n\t" \
	"movw %%ax,%%fs\n\t" \
	"movw %%ax,%%gs" \
	:::"ax")

#define sti() __asm__ ("sti"::)
#define cli() __asm__ ("cli"::)
#define nop() __asm__ ("nop"::)

#define iret() __asm__ ("iret"::)

/* 所有的 set_xx_gate都是以這個為基礎, 而這種寫法是GCC的嵌ASM的寫法,由左往右看
  _set_gate用於設置中斷向量表，即將interrupt[]和idt_table聯繫在一起
  gate_addr在此位置設置門描述符(是idt對應到的編號的ramaddr)
  type 門描述符類型(14,15)
  dpl特權級信息(即DPTR那個DPL)(0~3)
  addr中斷或異常處理過程地址
  先將%%dx的低16位移入%%ax的低16位(注意%%dx與%%edx的區別）//先將%%dx的低16位移入%%ax的低16位(注意%%dx與%%edx的區別）
  接著把第一個輸入立即數(0x8000+(dpl<<13)+(type<<8)裝入%%edx(也就是%dx)的低16位。( type為0x100,0x200 ~ 0xE00, 0xF00)
   然後再利用move long,把ax與dx分別移到gateaddr與gateaddr+4 */

/* "i" 立即數, "o" 操作數為內存變量，但是其尋址方式是偏移量類型， */
/* 以下d那行,因為param 0,1,2是包含在asm code裡面,所以真正要先input的是 d 與 a，也就是把 addr放到edx, 把0x00080000放到eax */
#define _set_gate(gate_addr,type,dpl,addr) \
__asm__ ("movw %%dx,%%ax\n\t" \
	"movw %0,%%dx\n\t" \
	"movl %%eax,%1\n\t" \
	"movl %%edx,%2" \
	: \
	: "i" ((short) (0x8000+(dpl<<13)+(type<<8))), \
	"o" (*((char *) (gate_addr))), \
	"o" (*(4+(char *) (gate_addr))), \
	"d" ((char *) (addr)),"a" (0x00080000))

/*
 * 如0號中斷的asm如下，會先設input(0x52f~541)，再來執行asm(0x546~54f)
	set_trap_gate(0,&divide_error);
 52f:	b9 00 00 00 00       	mov    $0x0,%ecx       // ecx用來存放gate_addr
 534:	b8 00 00 00 00       	mov    $0x0,%eax
 539:	8d 58 04             	lea    0x4(%eax),%ebx  // ebx用來存放gate_addr+4
 53c:	ba 00 00 00 00       	mov    $0x0,%edx       // 把addr 放到edx
 541:	b8 00 00 08 00       	mov    $0x80000,%eax   // 這個就是 "a"(0x80000)
 //====================== 以下為執行 ================================
 546:	66 89 d0             	mov    %dx,%ax
 549:	66 ba 00 8f          	mov    $0x8F00,%dx  // 如果是set_trap_gate，由於type=15(0x0f), dpl=0，所以算出來是0x8f00
 54d:	89 01                	mov    %eax,(%ecx)  // 把eax的值，移到gate_addr(即idt table)的記憶體位置
 54f:	89 13                	mov    %edx,(%ebx)
*/

#define set_intr_gate(n,addr) \
	_set_gate(&idt[n],14,0,addr) /* 根據編號,把idt對應到的編號的ram addr傳給set_gate */

#define set_trap_gate(n,addr) \
	_set_gate(&idt[n],15,0,addr)

#define set_system_gate(n,addr) \
	_set_gate(&idt[n],15,3,addr)

#define _set_seg_desc(gate_addr,type,dpl,base,limit) {\
	*(gate_addr) = ((base) & 0xff000000) | \
		(((base) & 0x00ff0000)>>16) | \
		((limit) & 0xf0000) | \
		((dpl)<<13) | \
		(0x00408000) | \
		((type)<<8); \
	*((gate_addr)+1) = (((base) & 0x0000ffff)<<16) | \
		((limit) & 0x0ffff); }

#define _set_tssldt_desc(n,addr,type) \
__asm__ ("movw $104,%1\n\t" \
	"movw %%ax,%2\n\t" \
	"rorl $16,%%eax\n\t" \
	"movb %%al,%3\n\t" \
	"movb $" type ",%4\n\t" \
	"movb $0x00,%5\n\t" \
	"movb %%ah,%6\n\t" \
	"rorl $16,%%eax" \
	::"a" (addr), "m" (*(n)), "m" (*(n+2)), "m" (*(n+4)), \
	 "m" (*(n+5)), "m" (*(n+6)), "m" (*(n+7)) \
	)

#define set_tss_desc(n,addr) _set_tssldt_desc(((char *) (n)),((int)(addr)),"0x89")
#define set_ldt_desc(n,addr) _set_tssldt_desc(((char *) (n)),((int)(addr)),"0x82")

