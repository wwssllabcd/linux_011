/*
 *  linux/init/main.c
 *
 *  (C) 1991  Linus Torvalds
 */

#define __LIBRARY__
#include <unistd.h>
#include <time.h>

/*
 * we need this inline - forking from kernel space will result
 * in NO COPY ON WRITE (!!!), until an execve is executed. This
 * is no problem, but for the stack. This is handled by not letting
 * main() use the stack at all after fork(). Thus, no function
 * calls - which means inline code for fork too, as otherwise we
 * would use the stack upon exit from 'fork()'.
 *
 * Actually only pause and fork are needed inline, so that there
 * won't be any messing with the stack from main(), but we define
 * some others too.
 */
static inline fork(void) __attribute__((always_inline));
static inline pause(void) __attribute__((always_inline));

// _syscall0為一define, 傳入type與name
// 也就是說，利用define的方式，做一個類似template，把fork,pause,setup,sync這四個function建立起來
// 舉fork來說，_syscall0建立了一個 int fork()的function，他傳入的參數為0, 所以也有syscall1(),syscall2(),等
static inline _syscall0(int, fork)

// Linux 的系統調用中斷0x80。該中斷是所有系統調用的
// 入口。該條語句實際上是int fork()創建進程系統調用。
// syscall0 名稱中最後的0 表示無參數，1 表示1 個參數。

//利用 define 來建立一個 int fork()的system call

static inline _syscall0(int,pause)
static inline _syscall1(int,setup,void *,BIOS)
static inline _syscall0(int,sync)

#include <linux/tty.h>
#include <linux/sched.h>
#include <linux/head.h>
#include <asm/system.h>
#include <asm/io.h>

#include <stddef.h>
#include <stdarg.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/types.h>

#include <linux/fs.h>

static char printbuf[1024];

extern int vsprintf();
extern void init(void);
extern void blk_dev_init(void);
extern void chr_dev_init(void);
extern void hd_init(void);
extern void floppy_init(void);
extern void mem_init(long start, long end);
extern long rd_init(long mem_start, int length);
extern long kernel_mktime(struct tm * tm);
extern long startup_time;

/*
 * This is set up by the setup-routine at boot-time
 */
#define EXT_MEM_K (*(unsigned short *)0x90002)
#define DRIVE_INFO (*(struct drive_info *)0x90080)
#define ORIG_ROOT_DEV (*(unsigned short *)0x901FC)

/*
 * Yeah, yeah, it's ugly, but I cannot find how to do this correctly
 * and this seems to work. I anybody has more info on the real-time
 * clock I'd be interested. Most of this was trial and error, and some
 * bios-listing reading. Urghh.
 */

#define CMOS_READ(addr) ({ \
		outb_p(0x80|addr,0x70); \
		inb_p(0x71); \
})

#define BCD_TO_BIN(val) ((val)=((val)&15) + ((val)>>4)*10)

static void time_init(void)
{
	struct tm time;

	do {
		time.tm_sec = CMOS_READ(0);
		time.tm_min = CMOS_READ(2);
		time.tm_hour = CMOS_READ(4);
		time.tm_mday = CMOS_READ(7);
		time.tm_mon = CMOS_READ(8);
		time.tm_year = CMOS_READ(9);
	} while (time.tm_sec != CMOS_READ(0));
	//一定要在一秒之內完成 time 結構

	BCD_TO_BIN(time.tm_sec);
	BCD_TO_BIN(time.tm_min);
	BCD_TO_BIN(time.tm_hour);
	BCD_TO_BIN(time.tm_mday);
	BCD_TO_BIN(time.tm_mon);
	BCD_TO_BIN(time.tm_year);
	time.tm_mon--;
	startup_time = kernel_mktime(&time);
}

static long memory_end = 0;
static long buffer_memory_end = 0;
static long main_memory_start = 0;

//第一個drive_info為type, 第二個drive_info為變數，而drive_info是對應到0x90080的資訊
struct drive_info { char dummy[32]; } drive_info;

void main(void)		/* This really IS void, no error here. */
{			/* The startup routine assumes (well, ...) this */
/*
 * Interrupts are still disabled. Do necessary setups, then
 * enable them
 */

 	ROOT_DEV = ORIG_ROOT_DEV; // ORIG_ROOT_DEV=0x901FC( 當初用 bios int 取得)
 	drive_info = DRIVE_INFO;  // 把0x90080的 RAM addr 解釋成drive_info(0x90080是存放硬碟參數表)
	memory_end = (1<<20) + (EXT_MEM_K<<10);  // EXT_MEM_K 是在 setup.S中取得
	memory_end &= 0xfffff000; //切齊 4k?

	// |----1M(kernel)---|---buffer(1,2,4M)---|-main_memory_start--主記憶體區--main_memory_end-|
	//linux 0.11系統最大 16MB，這邊看來只是讓他不要出過16MB
	if (memory_end > 16*1024*1024)
		memory_end = 16*1024*1024;


	// 根據目前記憶體大小，設定buffer的大小(buffer_memory_end的初值為0)
	// 由以下的 code看來，不管怎樣都會建立起一個 Buffer，只是說這個buffer大小為何而已
	if (memory_end > 12*1024*1024) 
		//如果 mem 大於 12MB, 就建立  4MB 的 buffer(高速緩衝)，見 linux 內核完全註釋P-660
		buffer_memory_end = 4*1024*1024;
	else if (memory_end > 6*1024*1024)
		//如果 mem 大於 6MB, 就建立  2MB 的 buffer 高速緩衝
		buffer_memory_end = 2*1024*1024;
	else
		buffer_memory_end = 1*1024*1024;//小於6MB記憶體的話, 就建立  1MB 的高速緩衝


	//根據機器記憶體大小不同, 調整main_memory_start的start addr
	main_memory_start = buffer_memory_end;

#ifdef RAMDISK
	main_memory_start += rd_init(main_memory_start, RAMDISK*1024);
#endif

	// 初始化記憶體的chain, 也就是初始化"mem_map"這個 array，buffer區設100(不可用), main區設0(可使用)
	// 看來buffer_end 接著之後就是 main_memory_start
	mem_init(main_memory_start, memory_end); // memory_end 看來是total memory的位置

	// 設定中斷與 IDT table
	trap_init();

	blk_dev_init();  //初始化 request[]
	chr_dev_init(); // 空的

	tty_init();
	time_init();
	sched_init();
	buffer_init(buffer_memory_end);
	hd_init();
	floppy_init();

	//Set Interrupt Flag(STI)開啟中斷。
	sti();

	//切換到x86 user mode
	move_to_user_mode();

	//fork其實是用 _syscall0產生出來的(_syscall0代表沒有參數)
	//int 0x80
	if (!fork()) {		/* we count on this going ok */
		init();
	}
/*
 *   NOTE!!   For any other task 'pause()' would mean we have to get a
 * signal to awaken, but task0 is the sole exception (see 'schedule()')
 * as task 0 gets activated at every idle moment (when no other tasks
 * can run). For task0 'pause()' just means we go check if some other
 * task can run, and if not we return here.
 */
	 /* 注意!! 對於任何其它的任務，'pause()'將意味著我們必須等待收到一個信號才會返
	   * 回就緒運行態，但任務0（task0）是唯一的意外情況（參見'schedule()'），因為任務0 在
	   * 任何空閒時間裡都會被激活（當沒有其它任務在運行時），因此對於任務0'pause()'僅意味著
	   * 我們返回來查看是否有其它任務可以運行，如果沒有的話我們就回到這裡，一直循環執行'pause()'。
	   */
	for(;;) pause();
}

static int printf(const char *fmt, ...)
{
	va_list args;
	int i;

	va_start(args, fmt);
	write(1,printbuf,i=vsprintf(printbuf, fmt, args));
	va_end(args);
	return i;
}

static char * argv_rc[] = { "/bin/sh", NULL };
static char * envp_rc[] = { "HOME=/", NULL };

static char * argv[] = { "-/bin/sh",NULL };
static char * envp[] = { "HOME=/usr/root", NULL };

void init(void)
{
	int pid,i;

	setup((void *) &drive_info);
	(void) open("/dev/tty0",O_RDWR,0);
	(void) dup(0);  //複製handle，產生handle1, stdout
	(void) dup(0);  //複製handle，產生handle2, stderr
	//這兩段會顯示在tty上面
	printf("%d buffers = %d bytes buffer space\n\r",NR_BUFFERS, NR_BUFFERS*BLOCK_SIZE);
	printf("Free mem: %d bytes\n\r",memory_end-main_memory_start);

	//利用fork來複製一個子進程
	if (!(pid=fork())) {
		close(0); //關閉handle_0(也就是stdin)

		//以唯讀的方式打開etc/rc，etc/rc有點類似autoexec.bat這個檔案
		if (open("/etc/rc",O_RDONLY,0))
			_exit(1);
		//子進程把自身變成shell後，執行shell，而該shell的參數分別為argv_rc,envp_rc(為固定值)
		execve("/bin/sh",argv_rc,envp_rc);

		//關閉handle0並且馬上打開/etc/rc是為了把stdin重新定到/etc/rc
		//而在執行rc文件後就會立刻退出，process2也就結束了
		_exit(2);
	}

	//這邊還是父進程(process(1))執行的地方
	if (pid>0)
		//父進程等待子進程結束，&i保存了子進程的result
		while (pid != wait(&i))
			/* nothing */;
	while (1) {
		if ((pid=fork())<0) {
			printf("Fork failed in init\r\n");
			continue;
		}
		if (!pid) {
			close(0);close(1);close(2);
			setsid();
			(void) open("/dev/tty0",O_RDWR,0);
			(void) dup(0);
			(void) dup(0);
			_exit(execve("/bin/sh",argv,envp));
		}
		while (1)
			if (pid == wait(&i))
				break;
		printf("\n\rchild %d died with code %04x\n\r",pid,i);
		sync();
	}
	_exit(0);	/* NOTE! _exit, not exit() */
}
