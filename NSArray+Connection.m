/* 
Copyright (c) 2004-2006 Karelia Software. All rights reserved.
 
 Redistribution and use in source and binary forms, with or without modification, 
 are permitted provided that the following conditions are met:
 
 
 Redistributions of source code must retain the above copyright notice, this list 
 of conditions and the following disclaimer.
 
 Redistributions in binary form must reproduce the above copyright notice, this 
 list of conditions and the following disclaimer in the documentation and/or other 
 materials provided with the distribution.
 
 Neither the name of Karelia Software nor the names of its contributors may be used to 
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
 
 */

#import "NSArray+Connection.h"
#import "NSObject+Connection.h"

@implementation NSArray (Connection)

#define NSARRAY_MAXIMUM_DESCRIBED 20

- (NSString *)shortDescription
{
	NSMutableString *str = [NSMutableString stringWithFormat:@"%@ [%d items]\n(\n", [self className], [self count]];
	
	unsigned i, c = MIN([self count], NSARRAY_MAXIMUM_DESCRIBED);
	
	for (i = 0; i < c; i++)
	{
		[str appendFormat:@"\t%@,\n", [[self objectAtIndex:i] shortDescription]];
	}
	[str deleteCharactersInRange:NSMakeRange([str length] - 2,2)];
	[str appendFormat:@"\n);"];
	
	return str;
}

/*The following are from Fugu (for SFTP usage)
 * Copyright (c) 2003 Regents of The University of Michigan. 
 */
- ( int )createArgv: ( char *** )argv
{
    char			**av;
    int				i, ac = 0, actotal;
    
    if ( self == nil || [ self count ] == 0 ) {
        *argv = NULL;
        return( 0 );
    }
    
    actotal = [ self count ];
    
    if (( av = ( char ** )malloc( sizeof( char * ) * actotal )) == NULL ) {
        NSLog( @"malloc: %s", strerror( errno ));
        exit( 2 );
    }
    
    for ( i = 0; i < [ self count ]; i++ ) {
        av[ i ] = ( char * )[[ self objectAtIndex: i ] UTF8String ];
        ac++;
        
        if ( ac >= actotal ) {
            if (( av = ( char ** )realloc( av, sizeof( char * ) * ( actotal + 10 ))) == NULL ) {
                NSLog( @"realloc: %s", strerror( errno ));
                exit( 2 );
            }
            actotal += 10;
        }
    }
    
    if ( ac >= actotal ) {
        if (( av = ( char ** )realloc( av, sizeof( char * ) * ( actotal + 10 ))) == NULL ) {
            NSLog( @"realloc: %s", strerror( errno ));
            exit( 2 );
        }
        actotal += 10; // clang complains "Value stored to 'actotal' is never read"
    }
    
    av[ i ] = NULL;
    *argv = av;
    
    return( ac );
}

@end
