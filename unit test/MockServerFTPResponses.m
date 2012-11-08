//
//  Created by Sam Deane on 06/11/2012.
//  Copyright 2012 Karelia Software. All rights reserved.
//

#import "MockServerFTPResponses.h"
#import "MockServer.h"

@implementation MockServerFTPResponses

+ (NSArray*)initialResponse
{
    return @[InitialResponseKey, @"220 $address FTP server ($server) ready.\r\n" ];
}

+ (NSArray*)userOkResponse
{
    return @[@"USER (\\w+)", @"331 User $1 accepted, provide password.\r\n"];
}

+ (NSArray*)passwordOkResponse
{
    return @[@"PASS (\\w+)", @"230 User user logged in.\r\n"];
}

+ (NSArray*)passwordBadResponse
{
    return @[@"PASS (\\w+)", @"530 Login incorrect.\r\n"];
}

+ (NSArray*)sysReponse
{
    return @[@"SYST", @"215 UNIX Type: L8 Version: $server\r\n" ];
}

+ (NSArray*)pwdResponse
{
    return @[@"PWD", @"257 \"/\" is the current directory.\r\n" ];
}

+ (NSArray*)typeResponse
{
    return @[@"TYPE (\\w+)", @"200 Type set to $1.\r\n" ];
}

+ (NSArray*)cwdResponse
{
    return @[@"CWD .*", @"250 CWD command successful.\r\n" ];
}

+ (NSArray*)pasvResponse
{
    return @[@"PASV", @"227 Entering Passive Mode ($pasv)\r\n"];
}

+ (NSArray*)sizeResponse
{
    return @[@"SIZE test.txt", @"213 $size\r\n"];
}

+ (NSArray*)retrResponse
{
    return @[@"RETR /test.txt", @"150 Opening BINARY mode data connection for '/test.txt' ($size bytes).\r\n"];
}

+ (NSArray*)listResponse
{
    return @[@"LIST", @(0.1), @"150 Opening ASCII mode data connection for '/bin/ls'.\r\n", @(0.1), @"226 Transfer complete.\r\n"];
}

+ (NSArray*)mkdResponse
{
    return @[ @"MKD (\\w+)", @"257 \"$1\" directory created.\r\n"];
}

+ (NSArray*)mkdFileExistsResponse
{
    return @[ @"MKD (\\w+)", @"550 $1: File exists.\r\n"];

}
+ (NSArray*)commandNotUnderstoodResponse
{
    return @[@"(\\w+).*", @"500 '$1': command not understood.", CloseCommand];
}

+ (NSArray*)standardResponses
{
    NSArray* responses = @[
    [self initialResponse],
    [self userOkResponse],
    [self passwordOkResponse],
    [self sysReponse],
    [self pwdResponse],
    [self typeResponse],
    [self cwdResponse],
    [self pasvResponse],
    [self sizeResponse],
    [self retrResponse],
    [self listResponse],
    [self mkdResponse],
    [self commandNotUnderstoodResponse],
    ];

    return responses;
}

+ (NSArray*)badLoginResponses
{
    NSArray* responses = @[
    [self initialResponse],
    [self userOkResponse],
    [self passwordBadResponse],
    [self commandNotUnderstoodResponse],
    ];

    return responses;
}

@end
