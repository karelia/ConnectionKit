Development
===========

ConnectionKit 2 is still under heavy development, but the front-end API is probably stable.

Things someone could do if they're feeling nice:

* Cancellation support for the File protocol
* Improve handling of invalid certificates for FTPS
* Amazon S3 protocol
* API for downloading/reading files

Features
========

ConnectionKit provides a Cocoa-friendly, block-based API for asynchronously working with:

* FTP, SFTP and WebDAV servers
* Local files

Contributors and Contact Info
=======

I'm Mike Abdullah, of [Karelia Software](http://karelia.com). [@mikeabdullah](http://twitter.com/mikeabdullah) on Twitter.

Questions about the code are best left as issues at https://github.com/karelia/ConnectionKit but you can also message me on Twitter (just don't expect more than a terse reply!).

Big thanks to:

* [Sam Deane](http://twitter.com/samdeane) of [Elegant Chaos](http://www.elegantchaos.com) for:
	* Sooo much testing, especially Mock Server
	* The WebDAV protocol implementation
	* Improving the File protocol implementation
* And all contributors to the submodules of course!

Dependencies
============

Requires OS X v10.6+

Relies upon CURLHandle and DAVKit. They are provided as submodules and may have their own dependencies in turn. Out of the box, provided you initialise all submodules, `CURLHandle.framework` should be able to nicely build, self-containing all its dependencies.

ConnectionKit supports both 64 and 32bit Macs. We hope to expand to iOS before too long too. Note that support for the legacy Objective-C runtime (32bit Mac) currently precludes switching the codebase to ARC.

License
=======

### CURLHandle

Please see https://github.com/karelia/CurlHandle for details of CURLHandle and its subcomponents' licensing.

### DAVKit

Please see https://github.com/karelia/DAVKit for details of CURLHandle and its subcomponents' licensing.

### Legacy

Existing ConnectionKit code should declare its licensing at the top of the file, most likely BSD or MIT.

### ConnectionKit 2 code

Licensed under the BSD License <http://www.opensource.org/licenses/bsd-license>
THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY
EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT
SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF
THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

Usage
=====

### Getting the code

1. Clone the ConnectionKit repository, ideally by adding it as a submodule if you're using git for your main project
2. Checkout the `curlhandle-4` branch
3. Initialise all submodules — they go several levels deep!
4. Add `Connection.xcodeproj` to your project
5. Add the ConnectionKit framework as a dependency of your project's build target
6. Set `Connection.framework` to be copied into a suitable location inside your build target; e.g the `Frameworks` directory

### Actually, y'know, doing stuff

1. Create a `CK2FileManager` instance
2. Set the file manager's delegate if you require control over authentication, or to receive transcripts. More details on auth are below
3. Instruct the file manager to do the thing what it is you want to do
4. The file manager will asynchronously call your completion handler when finished, to indicate success of the operation

Be sure to read through `CK2FileManager.h` as there's plenty of helpful documentation in there.

### Authentication

ConnectionKit follows a similar pattern to `NSURLConnection`: During an operation, it may vend out as many authentication challenges as it sees fit. Your delegate is responsible for replying to the challenges, instructing the connection how it ought to behave. Replying is asynchronous, giving you a chance to present some UI asking the user what they'd like to do if necessary.

#### WebDAV over HTTP

WebDAV servers can selectively choose whether to require authentication (e.g. public servers have no need to). If authentication is requested, you'll receive an authentication challenge encapsulating the auth method to be used (e.g. HTTP Digest). Respond with a username and password credential. ConnectionKit will do its best to supply `-proposedCredential` from the user's keychain.

#### FTP 

FTP is very similar to plain WebDAV, except it always asks for authentication. Usually, you respond with a username and password, but can ask to `-continueWithoutCredentialForAuthenticationChallenge:` for anonymous FTP login.

#### WebDAV over HTTPS

The validity of the server is checked first. This takes the form of potentially multiple challenges with the either of the following authentication methods:

* `NSURLAuthenticationMethodServerTrust`
* `NSURLAuthenticationMethodClientCertificate`
	
Generally it's best to call use `-performDefaultHandlingForAuthenticationChallenge:` to let Cocoa decide what to do.

#### SFTP

SFTP is a tricky blighter. You can opt to supply a username and password like other protocols. Our implementation also supports public key authentication, whereby you reply with a credential constructed using:

    +[NSURLCredential ck2_credentialWithUser:publicKeyURL:privateKeyURL:]

The public key is generally optional, as ConnectionKit can derive it from the private key. It's also possible to use SSH-Agent, but Apple discourage this, and it is unavailable to sandboxed apps.

Once connected to the server, ConnectionKit checks its fingerprint against the `~/.ssh/known_hosts` file. Note that for sandboxed apps this is inside of your container! An authentication challenge is issued with the result of this. Your delegate can call `-cancelAuthenticationChallenge:` to reject the fingerprint, or reply with a credential for acceptance, constructed using:

	+[NSURLCredential ck2_credentialForKnownHostWithPersistence:]

The default behaviour (`-performDefaultHandlingForAuthenticationChallenge:`) accepts new fingerprints, adding them to the `known_hosts` file, and causes the operation to fail with an error for mismatched fingerprints.

After checking the host fingerprint, SFTP moves on to actually authenticating the client. Legacy
======

For anyone relying on one of the old branches, they have been archived to be tags:

* master => v1.x
* release-1.2 => v1.2.x
* BrianWorkInProgress => brian-work-in-progress
* CKFTPResponse => ckftpresponse
* release-2.0 => experiment-2.0
