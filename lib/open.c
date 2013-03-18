/*
 *  linux/lib/open.c
 *
 *  (C) 1991  Linus Torvalds
 */

#define __LIBRARY__
#include <unistd.h>
#include <stdarg.h>

//// 打開文件函數(也許也是一個裝置，如tty)
// 打開並有可能創建一個文件。
// 參數：filename - 文件名；flag - 文件打開標誌；...
// 返回：文件描述符，若出錯則置出錯碼，並返回-1。
int open(const char * filename, int flag, ...)
{
	register int res;
	va_list arg;

	// 利用va_start()宏函數，取得"..." 的指針，然後調用系統中斷int 0x80，功能open 進行
	// 文件打開操作。
	// %0 - eax(返回的描述符或出錯碼)；%1 - eax(系統中斷調用功能號__NR_open)；
	// %2 - ebx(文件名filename)；%3 - ecx(打開文件標誌flag)；%4 - edx(後隨參數文件屬性mode)。
	va_start(arg,flag);
	__asm__("int $0x80"
		// 輸出部分， "=a"需要把"="與"a"分開來看，等號為輸出操作值，也就是把eax指給 res
		:"=a" (res)
		
		//輸入部分，把__NR_open(常數5)指給eax, 把filename指給ebx, 把flag指給ecx,把va_arg(arg,int)指給edx
		//也就是說system_call的輸入參數 分別存放在ebx，ecx，edx寄存器 中。
		//所以從這邊也可以推斷，int 80, type5類型用到的參數
		//簡單的講,就是執行int 0x80, 然後再中斷那邊, 根據eax來做中斷種類的dispatch
		
		:"0" (__NR_open),"b" (filename),"c" (flag),
		"d" (va_arg(arg,int)));
	
	// 系統中斷調用返回值大於或等於0，表示是一個文件描述符，則直接返回之。
	if (res>=0)
		return res;
	errno = -res;  // 否則說明返回值小於0，則代表一個出錯碼。設置該出錯碼並返回-1。
	return -1;
}


/*
//以下編譯出來的asm

open.o:     file format elf32-i386


Disassembly of section .text:

00000000 <open>:
#define __LIBRARY__
#include <unistd.h>
#include <stdarg.h>

int open(const char * filename, int flag, ...)
{
   0:	56                   	push   %esi
   1:	53                   	push   %ebx
   2:	83 ec 10             	sub    $0x10,%esp
	register int res;
	va_list arg;

	va_start(arg,flag);
   5:	8d 44 24 20          	lea    0x20(%esp),%eax
   9:	83 c0 04             	add    $0x4,%eax
   c:	89 44 24 0c          	mov    %eax,0xc(%esp)
	__asm__("int $0x80"
  10:	8b 4c 24 20          	mov    0x20(%esp),%ecx
		:"=a" (res)
		:"0" (__NR_open),"b" (filename),"c" (flag),
		"d" (va_arg(arg,int)));
  14:	83 44 24 0c 04       	addl   $0x4,0xc(%esp)
  19:	8b 44 24 0c          	mov    0xc(%esp),%eax
  1d:	83 e8 04             	sub    $0x4,%eax// eax減4
  20:	8b 10                	mov    (%eax),%edx  //指給D
{
	register int res;
	va_list arg;

	va_start(arg,flag);
	__asm__("int $0x80"
  22:	b8 05 00 00 00       	mov    $0x5,%eax // 這個就是"0" (__NR_open), 即把5這個常數，指給eax
  27:	8b 5c 24 1c          	mov    0x1c(%esp),%ebx
  2b:	89 c6                	mov    %eax,%esi
  2d:	89 f0                	mov    %esi,%eax
  2f:	cd 80                	int    $0x80
  31:	89 c6                	mov    %eax,%esi
  33:	89 f3                	mov    %esi,%ebx
		:"=a" (res)
		:"0" (__NR_open),"b" (filename),"c" (flag),
		"d" (va_arg(arg,int)));
	if (res>=0)
  35:	85 db                	test   %ebx,%ebx
  37:	78 04                	js     3d <open+0x3d>
		return res;
  39:	89 d8                	mov    %ebx,%eax
  3b:	eb 0e                	jmp    4b <open+0x4b>
	errno = -res;
  3d:	89 d8                	mov    %ebx,%eax
  3f:	f7 d8                	neg    %eax
  41:	a3 00 00 00 00       	mov    %eax,0x0
	return -1;
  46:	b8 ff ff ff ff       	mov    $0xffffffff,%eax
}
  4b:	83 c4 10             	add    $0x10,%esp //看來res是使用
  4e:	5b                   	pop    %ebx
  4f:	5e                   	pop    %esi
  50:	c3                   	ret


*/
