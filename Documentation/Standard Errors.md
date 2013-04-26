Protocols have wildly differing implementations, and those implementation can return wildly different errors in a given situation.

To some extent this is an impossible problem to solve, since it's unrealistic for us to provide a universal translation of all potential errors into some known set.

However, it is useful to be able to test for a few common errors, in specific situations, such as:

- authentication has failed
- we tried to make a directory but it was already there
- we tried to delete a directory but it wasn't there
- we tried to delete a file but it wasn't there

It's also helpful to wrap up all the other errors in some more generic catch-alls:

- something went wrong with something that reads/lists files
- something went wrong with writes/modifies/creates/destroys files


As a result, CK2Protocol defines some standard methods that protocol implementations can use to wrap up their own errors:

    - (NSError*)standardCouldntWriteErrorWithUnderlyingError:(NSError*)error;
    - (NSError*)standardCouldntReadErrorWithUnderlyingError:(NSError*)error;
    - (NSError*)standardFileNotFoundErrorWithUnderlyingError:(NSError*)error;
    - (NSError*)standardAuthenticationErrorWithUnderlyingError:(NSError*)error;

These methods will return, respectively:

    standardCouldntWriteErrorWithUnderlyingError: NSCocoaErrorDomain - NSFileWriteUnknownError
    standardCouldntReadErrorWithUnderlyingError: NSCocoaErrorDomain - NSFileNoSuchFileError
    standardFileNotFoundErrorWithUnderlyingError: NSCocoaErrorDomain - NSURLErrorNoPermissionsToReadFile
    standardAuthenticationErrorWithUnderlyingError: NSURLErrorDomain NSURLErrorUserAuthenticationRequired

Protocol implementations should ensure that they use these errors in the following situations:

Use standardAuthenticationErrorWithUnderlyingError to report any authentication problems (obviously).

Use standardFileNotFoundErrorWithUnderlyingError if the protocol implementation is sure that the underlying problem is caused by the file being absent. For example when deleting a directory or file that doesn't exist - assuming that the underlying protocol error is specific enough to know that this is the reason for the failure.

Use standardCouldntWriteErrorWithUnderlyingError when performing a createFile/createDirectory/removeFile/removeDirectory/setAttributes, if the protocol implementation's underlying error was too vague or definitely wasn't a file-not-found error.

Use standardCouldntReadErrorWithUnderlyingError when performing a enumating operation, if the protocol implementation's underlying error was too vague or definitely wasn't a file-not-found error.

One of the side benefits of this plan is that it allows us to write some unit tests that work generically across all supported protocols, since they now have some (vaguely) predictable errors to check against in the situations where the test is deliberately engineering an error situation.

Hopefully, though, this will also allow client code that uses multiple protocols to do something vaguely sensible with the errors that it gets back.

