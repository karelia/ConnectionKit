/*
 * Copyright (c) 2003 Regents of The University of Michigan.
 * All Rights Reserved.  See COPYRIGHT.
 */

#include "typeforchar.h"

    char *
typeforchar( int c )
{
    char	*type;
    
    switch ( c ) {
    case 'd':
        type = "directory";
        break;
    case '-':
        type = "file";
        break;
    case 'p':
        type = "named pipe";
        break;
    case 's':
        type = "socket";
        break;
    case 'b':
        type = "block special";
        break;
    case 'c':
        type = "char special";
        break;
    case 'l':
        type = "symbolic link";
        break;
    case 'D':
        type = "door";
        break;
    default:
        type = "unknown";
        break;
    }
    
    return( type );
}
        