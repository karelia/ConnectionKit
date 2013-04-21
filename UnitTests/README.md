A quick overview of the unit tests, since some of them are fairly involved.

# Server Configuration

Since some of the tests talk to servers, the tests can be configured using the defaults command:

    defaults write otest <key> <url>
    
with a key of CKWebDAVTest, CKFTPTest, or CKSFTPTest.

Setting the value to the url of a server will use that server for the tests.

Setting the value to "MockServer" will use MockServer (where possible).

Setting the value to "Off" will disable those tests.


# Tests

## CK2FileManagerPathTests

These test that [CK2FileManager pathOfURL] works correctly.



## CK2FileManagerFileTests

These test the file manager's support for file operations on the local machine (ie using file:// urls).



## CK2FileManagerFTPTests

These test the file manager's support for FTP and SFTP.

When the test suite is constructed, it actually makes two test suites containing the same tests, one using ftp and one sftp.

The underpinning inherited from CK2FileManagerBaseTests is used to ensure that the correct server value is read from the defaults, and the correct MockServer responses file is loaded if appropriate.


## CK2FileManagerFTPAuthenticationTests

This tests FTP support, in the specific situation where the first authentication attempt is bad, but the second one is good.



## CK2FileManagerURLTests

These test the CK2FileManager routines for creating URLs:

- [CK2FileManager URLWithPath:relativeToURL:]
- [CK2FileManager URLWithPath:hostURL:]


## CK2CURLProtocolURLManipulationTests

These perform various URL manipulation tests.

- Some tests check that NSURL is behaving as expected.
- Some check that CFURLHasDirectoryPath() hasn't changed behaviour.
- Some check that [CK2FTPProtocol newRequestWithRequest:isDirectory:] is working.


## CK2FileManagerBaseTests

This is a base class used by the other tests.

