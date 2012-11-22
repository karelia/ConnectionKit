/*
 Copyright (c) 2007, Ubermind, Inc
 All rights reserved.
 
 Redistribution and use in source and binary forms, with or without modification, 
 are permitted provided that the following conditions are met:
 
 Redistributions of source code must retain the above copyright notice, this list 
 of conditions and the following disclaimer.
 
 Redistributions in binary form must reproduce the above copyright notice, this 
 list of conditions and the following disclaimer in the documentation and/or other 
 materials provided with the distribution.
 
 Neither the name of Ubermind, Inc nor the names of its contributors may be used to 
 endorse or promote products derived from this software without specific prior 
 written permission.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY 
 EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES 
 OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT 
 SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, 
 INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED 
 TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR 
 BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY 
 WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 
 Authored by Greg Hulands <ghulands@mac.com>
 */

#import "NSNumber+Connection.h"


@implementation NSNumber (Connection)

- (BOOL)isExecutable
{
	unsigned long perms = [self unsignedLongValue];
	
	if (perms & 0100) return YES;
	if (perms & 010) return YES;
	if (perms & 01) return YES;
	
	return NO;
}

- (NSString *)permissionsStringValue
{
	NSMutableString *str = [NSMutableString string];
	unsigned long perm = [self unsignedLongValue];
	
	//owner
	if (perm & 0400)
	{
		[str appendString:@"r"];
	}
	else
	{
		[str appendString:@"-"];
	}
	if (perm & 0200)
	{
		[str appendString:@"w"];
	}
	else
	{
		[str appendString:@"-"];
	}
	if (perm & 0100)
	{
		[str appendString:@"x"];
	}
	else
	{
		[str appendString:@"-"];
	}

	//group
	if (perm & 040)
	{
		[str appendString:@"r"];
	}
	else
	{
		[str appendString:@"-"];
	}
	if (perm & 020)
	{
		[str appendString:@"w"];
	}
	else
	{
		[str appendString:@"-"];
	}
	if (perm & 010)
	{
		[str appendString:@"x"];
	}
	else
	{
		[str appendString:@"-"];
	}
	
	//world
	if (perm & 04)
	{
		[str appendString:@"r"];
	}
	else
	{
		[str appendString:@"-"];
	}
	if (perm & 02)
	{
		[str appendString:@"w"];
	}
	else
	{
		[str appendString:@"-"];
	}
	if (perm & 01)
	{
		[str appendString:@"x"];
	}
	else
	{
		[str appendString:@"-"];
	}
	return str;
}

@end
