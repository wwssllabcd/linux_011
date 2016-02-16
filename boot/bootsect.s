	.code16
# rewrite with AT&T syntax by falcon <wuzhangjin@gmail.com> at 081012
#
# SYS_SIZE is the number of clicks (16 bytes) to be loaded.
# 0x3000 is 0x30000 bytes = 196kB, more than enough for current
# versions of linux
#
	.equ SYSSIZE, 0x3000
#
#	bootsect.s		(C) 1991 Linus Torvalds
#
# bootsect.s is loaded at 0x7c00 by the bios-startup routines, and moves
# iself out of the way to address 0x90000, and jumps there.
#
# It then loads 'setup' directly after itself (0x90200), and the system
# at 0x10000, using BIOS interrupts. 
#
# NOTE! currently system is at most 8*65536 bytes long. This should be no
# problem, even in the future. I want to keep it simple. This 512 kB
# kernel size should be enough, especially as this doesn't contain the
# buffer cache as in minix
#
# The loader has been made as simple as possible, and continuos
# read errors will result in a unbreakable loop. Reboot by hand. It
# loads pretty fast by getting whole sectors at a time whenever possible.

	.global _start, begtext, begdata, begbss, endtext, enddata, endbss
	.text
	begtext:
	.data
	begdata:
	.bss
	begbss:
	.text

	.equ SETUPLEN, 4		# nr of setup-sectors
	.equ BOOTSEG, 0x07c0		# original address of boot-sector
	.equ INITSEG, 0x9000		# we move boot here - out of the way
	.equ SETUPSEG, 0x9020		# setup starts here
	.equ SYSSEG, 0x1000		# system loaded at 0x10000 (65536).
	.equ ENDSEG, SYSSEG + SYSSIZE	# where to stop loading

# ROOT_DEV:	0x000 - same type of floppy as boot.
#		0x301 - first partition on first drive etc
	.equ ROOT_DEV, 0x301       # 這邊代表要讀取那個裝置，0x301是讀取/dev/hda1，也可以替換其他裝置

	# ljmp CS,IP: 因為目前就是在07C0的位置，所以若要跳到 _start這個位置，而這個位置就是0x7C00 + _start 的 offset 的地方
	# 又因為CS是少一個0，所以這邊要填0x7C00變成0x07C0
	# 這邊一個是CS(BOOTSEG, 0x07c0), 一個是EIP(_start, 這邊就是_start的offset)，因為目前就是在0x07C0的位置
	ljmp    $BOOTSEG, $_start
_start:
	# 接下來就是把自己移動到 0x90000 的位置，為何要移動，是因為setup.S將參數表保存到那裡而預留空間
	mov	$BOOTSEG, %ax          # 把0x07C0 設給 ds, 把0x9000設給 es, 等下copy 的時候，會用到源地址的組合是 [ds:si], 相應的目標地址為[es:di]
	mov	%ax, %ds
	mov	$INITSEG, %ax          # 利用ax來設定es，雖然是9w，但實際上設定eS必須設定為9k，這樣CS:IP才會變成9w
	mov	%ax, %es
	mov	$256, %cx              # cx register通常拿來當counter, 也就是for loop中的 i，這邊打算要copy256個word到某地
	sub	%si, %si               # sub 是暫存器相減，這裡的意思同 xor %si, %si, 也就是si相減，清成0
	sub	%di, %di
	rep	                       # rep為repeat指令，他會根據CX值，當作repeat的次數
	movsw                      # movw AT&T 語法 是隱含操作數的，從 [ds:si]->[es:di], Intel語法好像是 movsw, 也就是copy data從 0x07C0到0x9000，相較於MOVSB，MOVSW是以WORD為單位
	ljmp	$INITSEG, $go      # 跳到 CS:IP = INITSEG:go 處，也就是不但把自己移到0x9000之外，也把目前執行處，從0x7Cxx移到0x90XX之後，接續著做下去

go:	mov	%cs, %ax               # copy完成後，把ds, es, ss 重設成 cs (0x9000)
	mov	%ax, %ds
	mov	%ax, %es
# put stack at 0x9ff00.
	mov	%ax, %ss
	mov	$0xFF00, %sp		   # arbitrary value >>512

# load the setup-sectors directly after the bootblock.
# Note that 'es' is already set up.
# 準備讀取sec 2 出來，此時sec 2 是放置 setup.S 的 code
# 使用int 13時，放置 data的地方是以 ES:BX 來代表
load_setup:
	mov	$0x0000, %dx		# drive 0, head 0           # DH=head, DL=drive
	mov	$0x0002, %cx		# sector 2, track 0         # CH=track, CL=startSector, 把 sec 2 讀出來(chs mode 是以sec 1 作為開始)
	mov	$0x0200, %bx		# address = 512, in INITSEG # address = ES*0x10 + BX, ES:BX 指向該service要存放在哪,由此可知這邊是要把data讀出來放到0x90200的位置
	.equ    AX, 0x0200+SETUPLEN                         # 這邊的值為0x0204, AH是0x02號 service (把data放到ram), AL 為讀幾個 sector
	mov     $AX, %ax		# service 2, nr of sectors
	int	$0x13			    # read it                   # INT 13H/AH=02H：讀取磁區
	jnc	ok_load_setup		# ok - continue
	
	#下reset disk cmd 之後，在跳到最前面，看起來沒有退路，讀到成功為止，否則就是死循環
	mov	$0x0000, %dx
	mov	$0x0000, %ax		# reset the diskette
	int	$0x13
	jmp	load_setup

ok_load_setup:

# Get disk drive parameters, specifically nr of sectors/track
# 把CX的內容(也就是cy與 sec per track)存在cs:sectors+0 中，sector 為一位置，在最下面有定義
# 要知道目前硬碟的 sector 位在哪，才知道還剩多少沒有讀取
	mov	$0x00, %dl          # DL= drive No, int 13, AH=8 = get param
	mov	$0x0800, %ax		# AH=8 is get drive parameters
	int	$0x13
	mov	$0x00, %ch          # 把 cylinder 設為0(應該是用不到的關係)
	#seg cs
	mov	%cx, %cs:sectors+0  # %cs means sectors is in %cs , 值為0x12
	mov	$INITSEG, %ax       # INITSEG的值為0x9000，因為讀取磁盤的參數會改掉ES，所以重設
	mov	%ax, %es

# Print some inane message
	# 使用int10, AH=3 先讀取 cursor 位置後，再以目前位置寫入, DX ＝ 圖形坐標列(X)、行(Y)
	mov	$0x03, %ah		# read cursor pos
	xor	%bh, %bh        # BH清成0
	int	$0x10           # AH=03H/INT 10H ，DH = Row, DL = Column
	
	mov	$24, %cx
	mov	$0x0007, %bx	# page 0, attribute 7 (normal)
	#lea	msg1, %bp
	mov $msg1, %bp      # ES:BP = Offset of string, 顯示load system..
	mov	$0x1301, %ax		# write string, move cursor  # AH=13:在Teletype模式下顯示字符串, AL＝像素值
	int	$0x10

# ok, we've written the message, now
# we want to load the system (at 0x10000)

	mov	$SYSSEG, %ax    # SYSSEG=0x1000,  system loaded at 0x10000 (65536)64k.
	mov	%ax, %es		# segment of 0x010000
	call	read_it     # read_it 在下面
	call	kill_motor

# After that we check which root-device to use. If the device is
# defined (#= 0), nothing is done and the given device is used.
# Otherwise, either /dev/PS0 (2,28) or /dev/at0 (2,8), depending
# on the number of sectors that the BIOS reports currently.

	#seg cs
	mov	%cs:root_dev+0, %ax  # root_dev 使用code 的方式 hard code, 預設值為 0x301
	cmp	$0, %ax              # 檢查該直是否為 0   
	jne	root_defined         # jne (jump not equal) 	不等於則轉移 	檢查 zf=0
	#seg cs
	mov	%cs:sectors+0, %bx
	mov	$0x0208, %ax		# /dev/ps0 - 1.2Mb
	cmp	$15, %bx
	je	root_defined
	mov	$0x021c, %ax		# /dev/PS0 - 1.44Mb
	cmp	$18, %bx
	je	root_defined
undef_root:
	jmp undef_root
root_defined:
	#seg cs
	mov	%ax, %cs:root_dev+0

# after that (everyting loaded), we jump to
# the setup-routine loaded directly after
# the bootblock:

	ljmp	$SETUPSEG, $0  # 跳到0x90200，執行setup.S

# This routine loads the system at address 0x10000, making sure
# no 64kB boundaries are crossed. We try to load it as fast as
# possible, loading whole tracks whenever we can.
#
# in:	es - starting address segment (normally 0x1000)
#
sread:	.word 1+ SETUPLEN	# sectors read of current track
head:	.word 0			# current head
track:	.word 0			# current track

#要把 system從磁碟讀到0x10000的位置
read_it:
	mov		%es, %ax        # es已經被設定為 0x1000
	test	$0x0fff, %ax    # 測試 es 是否為 0x1000
die:	
	jne 	die				# es must be at 64kB boundary(也就是es = 0x1000), 所以不對就進入死循環
	xor 	%bx, %bx		# bx is starting address within segment ,設 bx =0 代表 ES:BX = 0x1000:0
rp_read:
	mov 	%es, %ax        # 檢查目前 ES 是否已經到達 0x3000 
 	cmp 	$ENDSEG, %ax	# have we loaded all yet? # sys_start = 0x1000, sts_end = 0x3000 ，所以大小為100個sector?
	jb		ok1_read        # 如果已經到底了，就 return
	ret
ok1_read:
	#seg cs
	mov		%cs:sectors+0, %ax   # 讀取之前的 secPerTrack/cylinder, 這邊是0x12
	sub		sread, %ax           # ax = ax - sread , 也就是 0x12 - 5 = 0x0d, 還剩 0x0d 個 sec 要讀
	mov		%ax, %cx
	shl		$9, %cx              # 也就是 cx * 512, 代表這次打算要讀多少sector, 為 0x0d*0x200 = 0x1a00
	add		%bx, %cx			 # 因為 bx 為int 13 的 ES:BX, 所以 cx = bx+cx 是利用cx來測試這次的讀取動作有沒有 overflow
	jnc 	ok2_read             # cf =0, 如果沒有 overflow, 就可以執行這次的read, 否則要調整 read 的 sector
	je 		ok2_read
	xor 	%ax, %ax             # 這裡看起來是處理 BX已經過頭的地方
	sub 	%bx, %ax             # 現在的bx 就是代表 overflow 多少個byte, 減去0，代表要讀多少byte出來
	shr 	$9, %ax              # ax 除512, 則代表要讀多少個sector
ok2_read:
	call 	read_track       # 要跳進去之前，AL要先設定好，代表本次要讀多少sector
	mov 	%ax, %cx         # ax = 這次操作所讀的sector數, 即 0x0d
	add 	sread, %ax       # ax = 已經讀多少sector 0x05 +0x0d => %ax = 0x12
	#seg cs
	cmp 	%cs:sectors+0, %ax   # 比較"secPerTrack"與"目前讀取多少sector" ，如果一樣，就往下執行
	jne 	ok3_read
	mov 	$1, %ax
	sub 	head, %ax        # 看看head是否為1, ax - head = ax
	jne 	ok4_read         # 如果head目前是0,則會跳到 ok4_read 去執行
	incw    track            # 如果head為1 ，則 track + 1
ok4_read:
	mov	%ax, head      # head設為1
	xor	%ax, %ax       # ax 設0 
ok3_read:
	mov	%ax, sread     # ax 若是讀為整個track的話，則為0, 否則為 %cs:sectors，即secPerTrack
	shl	$9, %cx		   # cx 為這次讀多少sector, 為 0x0d*512
	add	%cx, %bx       # 把目前讀到哪的offset , 重新設給 bx, 因為int 13 read 是靠 ES:BX
	jnc	rp_read        # 如果無進位符號，則跳躍 if cf==0, then jump rp_read
	mov	%es, %ax       # 這邊看起來是控制 ES 是否 需要 + 0x1000的地方
	add	$0x1000, %ax
	mov	%ax, %es
	xor	%bx, %bx
	jmp	rp_read

read_track:
	push	%ax
	push	%bx
	push	%cx       
	push	%dx
	mov	track, %dx
	mov	sread, %cx
	inc	%cx            # CL = sector number 1-63 (bits 0-5), 這邊固定 +1, 因為sec是從1開始
	mov	%dl, %ch
	mov	head, %dx      # 取出 head
	mov	%dl, %dh       # DH = head number
	mov	$0, %dl        # DL = drive number (bit 7 set for hard disk)
	and	$0x0100, %dx   # 做 and 運算, 結果應該是 dx=0, 這意思是，只會讀到header 1?
	mov	$2, %ah        # int 13, AH=2 :READ SECTOR(S) INTO MEMORY, AL = number of sectors to read (must be nonzero)
	int	$0x13          # 第一次進來的時候，AX是keep住還剩多少sec, 也就是 0x0d, 讀到 ES:BX, ES之前設過是0x1000
	 
	jc	bad_rt
	pop	%dx
	pop	%cx            # cx 為，這次的op, 到底讀出多少byte 
	pop	%bx
	pop	%ax
	ret
bad_rt:	mov	$0, %ax
	mov	$0, %dx
	int	$0x13
	pop	%dx
	pop	%cx
	pop	%bx
	pop	%ax
	jmp	read_track

#/*
# * This procedure turns off the floppy drive motor, so
# * that we enter the kernel in a known state, and
# * don't have to worry about it later.
# */
kill_motor:
	push	%dx
	mov		$0x3f2, %dx
	mov		$0, %al
	outsb
	pop		%dx
	ret

sectors:
	.word 0

msg1:
	.byte 13,10
	.ascii "Loading system ..."
	.byte 13,10,13,10

	.org 508
root_dev:
	.word ROOT_DEV
boot_flag:
	.word 0xAA55
	
	.text
	endtext:
	.data
	enddata:
	.bss
	endbss:
