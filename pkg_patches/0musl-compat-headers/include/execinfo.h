/*
 * see also https://github.com/ianlancetaylor/libbacktrace
 * 
Copyright (c) 2016-2022 Adélie Linux and its contributors.
All rights reserved.

Developed by: 		Wilcox Technologies Inc., A. Wilcox,
                        Ariadne Conill, and contributors
                        https://www.adelielinux.org/

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal with the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject
to the following conditions:

Redistributions of source code must retain the above copyright
notice, this list of conditions and the following disclaimers.

Redistributions in binary form must reproduce the above copyright
notice, this list of conditions and the following disclaimers in
the documentation and/or other materials provided with the distribution.

Neither the names of Adélie Linux nor the names of its contributors may
be used to endorse or promote products derived from this Software
without specific prior written permission.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE CONTRIBUTORS OR COPYRIGHT HOLDERS BE LIABLE
FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF
CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE.
*/

#ifndef _EXECINFO_H
#define _EXECINFO_H 1

#include <dlfcn.h>  /* dladdr */
#include <stddef.h> /* NULL */
#include <stdint.h> /* uintptr_t */
#include <stdlib.h> /* calloc */
#include <string.h> /* strlen */
#include <unistd.h> /* write */

#define get_frame_level(array, size, n)                                        \
	do {                                                                   \
		if (n >= size || __builtin_frame_address(n) == NULL) {         \
			return n;                                              \
		}                                                              \
		void *address = __builtin_return_address(n);                   \
		array[n] = __builtin_extract_return_addr(address);             \
		if ((uintptr_t) array[n] < 0x1000) {                           \
			return n;                                              \
		}                                                              \
	} while (0)

/**
 * Obtain a backtrace for the calling program.
 *
 * LSB 5.0: LSB-Core-generic/baselib-backtrace-1.html
 */
static int backtrace(void **array, int size)
{
	get_frame_level(array, size, 0);
	get_frame_level(array, size, 1);
	get_frame_level(array, size, 2);
	get_frame_level(array, size, 3);
	get_frame_level(array, size, 4);
	get_frame_level(array, size, 5);
	get_frame_level(array, size, 6);
	get_frame_level(array, size, 7);
	get_frame_level(array, size, 8);
	get_frame_level(array, size, 9);
	return 10;
}

/**
 * Translate addresses into symbol information.
 *
 * LSB 5.0: LSB-Core-generic/baselib-backtrace-1.html
 */
static const char **backtrace_symbols(void *const *array, int size)
{
	const char **result = calloc(size, sizeof(char *));

	if (result == NULL) {
		return NULL;
	}
	for (int i = 0; i < size; ++i) {
		Dl_info info;

		if (dladdr(array[i], &info) && info.dli_sname != NULL) {
			result[i] = info.dli_sname;
		} else {
			result[i] = "??:0";
		}
	}

	return result;
}

/**
 * Write symbol information to a file without allocating memory.
 *
 * LSB 5.0: LSB-Core-generic/baselib-backtrace-1.html
 */
static void backtrace_symbols_fd(void *const *array, int size, int fd)
{
	for (int i = 0; i < size; ++i) {
		Dl_info info;
		const char *line;
		int len;

		if (dladdr(array[i], &info) && info.dli_sname != NULL) {
			line = info.dli_sname;
			len = strlen(line);
		} else {
			line = "??:0";
			len = sizeof("??:0") - 1;
		}
		while (len > 0) {
			int written = write(fd, line, len);

			if (written < 1) {
				return;
			}
			line += written;
			len -= written;
		}
		if (write(fd, "\n", 1) != 1) {
			return;
		}
	}
}

#endif /* execinfo.h  */
