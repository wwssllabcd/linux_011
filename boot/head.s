/*
 *  linux/boot/head.s
 *
 *  (C) 1991  Linus Torvalds
 */

/*
 *  head.s contains the 32-bit startup code.
 *
 * NOTE!!! Startup happens at absolute address 0x00000000, which is also where
 * the page directory will exist. The startup code will be overwritten by
 * the page directory.
 */
.text
.globl idt,gdt,pg_dir,tmp_floppy_area
pg_dir:
.globl startup_32
startup_32:
	movl $0x10,%eax         # 0x10 代表 0x08 + 0x02, 則是GDT 1 ，並且特權級為2,見 linux 011. P89
	mov %ax,%ds
	mov %ax,%es
	mov %ax,%fs
	mov %ax,%gs
	lss stack_start,%esp    # load ss, 把這個位置，讀到 SS:ESP中
	call setup_idt          # 初始IDT, 即把每個 interrup 都填成 ignore_int(即unknow interrup，啞中斷)的位置
	call setup_gdt          # 單純 load gdt desc
	movl $0x10,%eax		    # reload all the segment registers
	mov %ax,%ds		        # after changing gdt. CS was already
	mov %ax,%es		        # reloaded in 'setup_gdt'
	mov %ax,%fs
	mov %ax,%gs
	lss stack_start,%esp
	xorl %eax,%eax          # eax=0
1:	incl %eax		        # check that A20 really IS enabled
	movl %eax,0x000000	    # loop forever if it isn't
	cmpl %eax,0x100000      # 檢查 0x000000 與 0x100000 的值相, 如果相同，就跳到標號1, 代表沒開A20
	je 1b

/*
 * NOTE! 486 should set bit 16, to check for write-protect in supervisor
 * mode. Then it would be unnecessary with the "verify_area()"-calls.
 * 486 users probably want to set the NE (#5) bit also, so as to use
 * int 16 for math errors.
 */
	movl %cr0,%eax		# check math chip
	andl $0x80000011,%eax	# Save PG,PE,ET
/* "orl $0x10020,%eax" here for 486 might be good */
	orl $2,%eax		# set MP
	movl %eax,%cr0
	call check_x87
	jmp after_page_tables  //最後一個指令，且不會再回來

/*
 * We depend on ET to be correct. This checks for 287/387.
 */
check_x87:
	fninit
	fstsw %ax
	cmpb $0,%al
	je 1f			/* no coprocessor: have to set bits */
	movl %cr0,%eax
	xorl $6,%eax		/* reset MP, set EM */
	movl %eax,%cr0
	ret
.align 2
1:	.byte 0xDB,0xE4		/* fsetpm for 287, ignored by 387 */
	ret

/*
 *  setup_idt
 *
 *  sets up a idt with 256 entries pointing to
 *  ignore_int, interrupt gates. It then loads
 *  idt. Everything that wants to install itself
 *  in the idt-table may do so themselves. Interrupts
 *  are enabled elsewhere, when we can be relatively
 *  sure everything is ok. This routine will be over-
 *  written by the page tables.
 */
setup_idt:
	lea ignore_int,%edx    // 把 ignore_int 這個 function offset 的值，放到 edx 中
	movl $0x00080000,%eax  // 這邊的 edx 是存放 idt的高4 byte, 而 eax 存放的是低4 byte, selector = 0x0008 = cs
	movw %dx,%ax		   /* 把 eax 組合成 segment selector(前2 byte) + function offset(後2 byte)   */
	movw $0x8E00,%dx	   /* edx的低 2 byte 是設定權限，固定為 0x8E00, interrupt gate - dpl=0, present */

	lea idt,%edi           // edi 為 idt所在的offset, 而 idt 在本檔案的最後面，為256個item, 所以大小為 256*8 = 2048
	mov $256,%ecx          /* 設置repeat 256次, 因為idt最多256個 */
rp_sidt:
	movl %eax,(%edi)       /* edi為 idt的位置所在，組合低4 byte  */
	movl %edx,4(%edi)      // 設定高4 byte 
	addl $8,%edi           /* 移動edi+=8 */
	dec %ecx               /* ecx為次數 */
	jne rp_sidt
	lidt idt_descr         /* load idt table的位置到iDPTR */
	ret

/*
 *  setup_gdt
 *
 *  This routines sets up a new gdt and loads it.
 *  Only two entries are currently built, the same
 *  ones that were built in init.s. The routine
 *  is VERY complicated at two whole lines, so this
 *  rather long comment is certainly needed :-).
 *  This routine will beoverwritten by the page tables.
 */
setup_gdt:
	lgdt gdt_descr
	ret

/*
 * I put the kernel page tables right after the page directory,
 * using 4 of them to span 16 Mb of physical memory. People with
 * more than 16MB will have to expand this.
 */
.org 0x1000
pg0:

.org 0x2000
pg1:

.org 0x3000
pg2:

.org 0x4000
pg3:

.org 0x5000
/*
 * tmp_floppy_area is used by the floppy-driver when DMA cannot
 * reach to a buffer-block. It needs to be aligned, so that it isn't
 * on a 64kB border.
 */
tmp_floppy_area:
	.fill 1024,1,0

after_page_tables:
	pushl $0		 # These are the parameters to main :-)
	pushl $0
	pushl $0
	pushl $L6		 # return address for main, if it decides to.(如果不小心從main return時，會jump到L6)
	pushl $main      # 預計返回的時候跳到main ?
	jmp setup_paging # 這邊使用jmp而不使用call的原因是因為call會把current ip壓入 stack, 而jmp不會，而ret指令會把stack pop出來
L6:
	jmp L6			 # main should never return here, but
				     # just in case, we know what happens.

/* This is the default interrupt "handler" :-) */
int_msg:
	.asciz "Unknown interrupt\n\r"
.align 2
ignore_int:
	pushl %eax  # backup register
	pushl %ecx
	pushl %edx  # end backup
	push %ds    # backup segment register
	push %es
	push %fs
	movl $0x10,%eax
	mov %ax,%ds
	mov %ax,%es
	mov %ax,%fs
	pushl $int_msg
	call printk
	popl %eax
	pop %fs
	pop %es
	pop %ds
	popl %edx   # restore register
	popl %ecx
	popl %eax
	iret


/*
 * Setup_paging
 *
 * This routine sets up paging by setting the page bit
 * in cr0. The page tables are set up, identity-mapping
 * the first 16MB. The pager assumes that no illegal
 * addresses are produced (ie >4Mb on a 4Mb machine).
 *
 * NOTE! Although all physical memory should be identity
 * mapped by this routine, only the kernel page functions
 * use the >1Mb addresses directly. All "normal" functions
 * use just the lower 1Mb, or the local data space, which
 * will be mapped to some other place - mm keeps track of
 * that.
 *
 * For those with more memory than 16 Mb - tough luck. I've
 * not got it, why should you :-) The source is here. Change
 * it. (Seriously - it shouldn't be too difficult. Mostly
 * change some constants etc. I left it at 16Mb, as my machine
 * even cannot be extended past that (ok, but it was cheap :-)
 * I've tried to show which constants to change by having
 * some kind of marker at them (search for "16Mb"), but I
 * won't guarantee that's all :-( )
 */
.align 2
setup_paging:
	movl $1024*5,%ecx		/* 5 pages - pg_dir+4 page tables , 這邊的cx應該是當作count */ 
	xorl %eax,%eax
	xorl %edi,%edi			/* pg_dir is at 0x000 */
	cld;rep;stosl           // 把eax的值，存到 ES:edi上，且一次加4
	movl $pg0+7,pg_dir		/* set present bit/user r/w */
	movl $pg1+7,pg_dir+4	// pg_dir 位在 addr=0的位置，這邊把$pg0+7(也就是0x1007)，存入addr=0的位置
	movl $pg2+7,pg_dir+8	// 而這邊的 code 不會被蓋到的原因是因為 這段code 放在 .org 0x5000 的原因
	movl $pg3+7,pg_dir+12	
	movl $pg3+4092,%edi
	movl $0xfff007,%eax		/*  16Mb - 4096 + 7 (r/w user,p) */
	std                     
1:	stosl			        /* fill pages backwards - more efficient :-) */
	subl $0x1000,%eax       // 利用eax 遞減0x1000, 把所有的page table的值填正確, 如fff007,ffe007,fffd007等
	jge 1b
	cld
	xorl %eax,%eax		   /* pg_dir is at 0x0000 */
	movl %eax,%cr3		   /* cr3 - page directory start */
	movl %cr0,%eax
	orl $0x80000000,%eax
	movl %eax,%cr0		   /* set paging (PG) bit */
	ret			           /* this also flushes prefetch-queue */

.align 2
.word 0
idt_descr:          # 低的2 byte, 代表table長度, 高的4 byte為 table 所在的offset , 同 gdt descriptor
	.word 256*8-1	# idt contains 256 entries
	.long idt
.align 2
.word 0
gdt_descr:          # 低的2 byte, 代表table長度, 高的4 byte為 table 所在的offset , 同 idt descriptor
	.word 256*8-1	# so does gdt (not that that's any
	.long gdt		# magic number, but it works for me :^)

	.align 8
idt:	.fill 256,8,0		# idt is uninitialized

gdt:	
	.quad 0x0000000000000000	/* NULL descriptor */
	.quad 0x00c09a0000000fff	/* 16Mb */
	.quad 0x00c0920000000fff	/* 16Mb */
	.quad 0x0000000000000000	/* TEMPORARY - don't use */
	.fill 252,8,0			/* space for LDT's and TSS's etc */

/*
設定GDT, 每條Segment Descriptor 各8 BYTE, 如0x00c0,9a00,0000,0fff
LSM的最後16 bit為限制長度，這邊為0x0FFF代表限制4096個單位，也就是 4k*4096 = 16M

第0個段為NULL(規定)
第1個段的參數為0x9A，可知為 可執行/可讀的 code段
第2個段的參數為0x92，可知為 可讀/寫的 data段

而這兩個段的base都是指向0的位置，這裡的資料同setup.S所設定的一樣，不一樣的是，這個table是位在 address 0 的地方(setup的是在0x92000)
*/





