/*
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

#ifndef _ERROR_H
#define _ERROR_H 1

/**
#include <errno.h>
#include <err.h>
#define error(status,errnum,format,...) err(status,format,__VA_ARGS__)
**/

#define _GNU_SOURCE /* program_invocation_name */
#include <errno.h>  /* program_invocation_name */
#include <stdarg.h> /* va_list, va_start, va_end */
#include <stdio.h>  /* fflush, fputc, fputs, stderr, stdout, vfprintf */
#include <string.h> /* strerror */

/**
 * Print an error message.
 *
 * LSB 5.0: LSB-Core-generic/baselib-error-n.html
 */
static void error(int status, int errnum, const char *format, ...)
{
	va_list ap;

	fflush(stdout);
	fputs(program_invocation_name, stderr);
	fputs(": ", stderr);
	va_start(ap, format);
	vfprintf(stderr, format, ap);
	va_end(ap);
	if (errnum != 0) {
		fputs(": ", stderr);
		fputs(strerror(errnum), stderr);
	}
	fputc('\n', stderr);
}

#endif /* error.h  */
