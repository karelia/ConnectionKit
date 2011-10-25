/* Copyright (c) 2004-2007, Sara Golemon <sarag@libssh2.org>
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms,
 * with or without modification, are permitted provided
 * that the following conditions are met:
 *
 *   Redistributions of source code must retain the above
 *   copyright notice, this list of conditions and the
 *   following disclaimer.
 *
 *   Redistributions in binary form must reproduce the above
 *   copyright notice, this list of conditions and the following
 *   disclaimer in the documentation and/or other materials
 *   provided with the distribution.
 *
 *   Neither the name of the copyright holder nor the names
 *   of any other contributors may be used to endorse or
 *   promote products derived from this software without
 *   specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND
 * CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES,
 * INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
 * OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
 * CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
 * BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
 * WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
 * NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE
 * USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY
 * OF SUCH DAMAGE.
 */

#ifndef LIBSSH2_PRIV_H
#define LIBSSH2_PRIV_H 1

#define LIBSSH2_LIBRARY
#include "libssh2_config.h"
#include "libssh2.h"

#include <stdio.h>

#ifndef WIN32
#include <sys/socket.h>
#endif

#ifdef LIBSSH2_LIBGCRYPT
#include "libgcrypt.h"
#else
#include "openssl.h"
#endif

#define LIBSSH2_ALLOC(session, count)								session->alloc((count), &(session)->abstract)
#define LIBSSH2_REALLOC(session, ptr, count)						((ptr) ? session->realloc((ptr), (count), &(session)->abstract) : session->alloc((count), &(session)->abstract))
#define LIBSSH2_FREE(session, ptr)									session->free((ptr), &(session)->abstract)

#define LIBSSH2_IGNORE(session, data, datalen)						session->ssh_msg_ignore((session), (data), (datalen), &(session)->abstract)
#define LIBSSH2_DEBUG(session, always_display, message, message_len, language, language_len)	\
				session->ssh_msg_disconnect((session), (always_display), (message), (message_len), (language), (language_len), &(session)->abstract)
#define LIBSSH2_DISCONNECT(session, reason, message, message_len, language, language_len)	\
				session->ssh_msg_disconnect((session), (reason), (message), (message_len), (language), (language_len), &(session)->abstract)

#define LIBSSH2_MACERROR(session, data, datalen)					session->macerror((session), (data), (datalen), &(session)->abstract)
#define LIBSSH2_X11_OPEN(channel, shost, sport)						channel->session->x11(((channel)->session), (channel), (shost), (sport), (&(channel)->session->abstract))

#define LIBSSH2_CHANNEL_CLOSE(session, channel)						channel->close_cb((session), &(session)->abstract, (channel), &(channel)->abstract)

#define LIBSSH2_WRITE(session, buffer, length)						session->ssh_write((uint8_t *)buffer, length, session, session->userInfo)
#define LIBSSH2_READ(session, buffer, length)						session->ssh_read((uint8_t *)buffer, length, session, session->userInfo)

typedef struct _LIBSSH2_KEX_METHOD			LIBSSH2_KEX_METHOD;
typedef struct _LIBSSH2_HOSTKEY_METHOD		LIBSSH2_HOSTKEY_METHOD;
typedef struct _LIBSSH2_MAC_METHOD			LIBSSH2_MAC_METHOD;
typedef struct _LIBSSH2_CRYPT_METHOD		LIBSSH2_CRYPT_METHOD;
typedef struct _LIBSSH2_COMP_METHOD			LIBSSH2_COMP_METHOD;

typedef struct _LIBSSH2_PACKET				LIBSSH2_PACKET;
typedef struct _LIBSSH2_PACKET_BRIGADE		LIBSSH2_PACKET_BRIGADE;
typedef struct _LIBSSH2_CHANNEL_BRIGADE		LIBSSH2_CHANNEL_BRIGADE;

struct _LIBSSH2_PACKET {
	unsigned char type;

	/* Unencrypted Payload (no type byte, no padding, just the facts ma'am) */
	unsigned char *data;
#warning 64BIT: Inspect use of unsigned long
	unsigned long data_len;

	/* Where to start reading data from,
	 * used for channel data that's been partially consumed */
#warning 64BIT: Inspect use of unsigned long
	unsigned long data_head;

	/* Can the message be confirmed? */
	NSInteger mac;

	LIBSSH2_PACKET_BRIGADE *brigade;

	LIBSSH2_PACKET *next, *prev;
};

struct _LIBSSH2_PACKET_BRIGADE {
	LIBSSH2_PACKET *head, *tail;
};

typedef struct _libssh2_channel_data {
	/* Identifier */
#warning 64BIT: Inspect use of unsigned long
	unsigned long id;

	/* Limits and restrictions */
#warning 64BIT: Inspect use of unsigned long
	unsigned long window_size_initial, window_size, packet_size;

	/* Set to 1 when CHANNEL_CLOSE / CHANNEL_EOF sent/received */
	char close, eof, extended_data_ignore_mode;
} libssh2_channel_data;

struct _LIBSSH2_CHANNEL {
	unsigned char *channel_type;
	NSUInteger channel_type_len;

	NSInteger blocking;

	/* channel's program exit status */
	NSInteger exit_status;

	libssh2_channel_data local, remote;
#warning 64BIT: Inspect use of unsigned long
	unsigned long adjust_queue; /* Amount of bytes to be refunded to receive window (but not yet sent) */

	LIBSSH2_SESSION *session;

	LIBSSH2_CHANNEL *next, *prev;

	void *abstract;
	LIBSSH2_CHANNEL_CLOSE_FUNC((*close_cb));
};

struct _LIBSSH2_CHANNEL_BRIGADE {
	LIBSSH2_CHANNEL *head, *tail;
};

struct _LIBSSH2_LISTENER {
	LIBSSH2_SESSION *session;

	char *host;
	NSInteger port;

	LIBSSH2_CHANNEL *queue;
	NSInteger queue_size;
	NSInteger queue_maxsize;

	LIBSSH2_LISTENER *prev, *next;
};

typedef struct _libssh2_endpoint_data {
	unsigned char *banner;

	unsigned char *kexinit;
#warning 64BIT: Inspect use of unsigned long
	unsigned long kexinit_len;

	LIBSSH2_CRYPT_METHOD *crypt;
	void *crypt_abstract;

	LIBSSH2_MAC_METHOD *mac;
#warning 64BIT: Inspect use of unsigned long
	unsigned long seqno;
	void *mac_abstract;

	LIBSSH2_COMP_METHOD *comp;
	void *comp_abstract;

	/* Method Preferences -- NULL yields "load order" */
	char *crypt_prefs;
	char *mac_prefs;
	char *comp_prefs;
	char *lang_prefs;
} libssh2_endpoint_data;

struct _LIBSSH2_SESSION {
	/* Memory management callbacks */
	void *abstract;
	LIBSSH2_ALLOC_FUNC((*alloc));
	LIBSSH2_REALLOC_FUNC((*realloc));
	LIBSSH2_FREE_FUNC((*free));
	
	/* Read/Write callbacks */
	LIBSSH2_WRITE_FUNC((*ssh_write));
	LIBSSH2_READ_FUNC((*ssh_read));
	void *userInfo;
	
	/* Other callbacks */
	LIBSSH2_IGNORE_FUNC((*ssh_msg_ignore));
	LIBSSH2_DEBUG_FUNC((*ssh_msg_debug));
	LIBSSH2_DISCONNECT_FUNC((*ssh_msg_disconnect));
	LIBSSH2_MACERROR_FUNC((*macerror));
	LIBSSH2_X11_OPEN_FUNC((*x11));

	/* Method preferences -- NULL yields "load order" */
	char *kex_prefs;
	char *hostkey_prefs;

	NSInteger state;
	NSInteger flags;

	/* Agreed Key Exchange Method */
	LIBSSH2_KEX_METHOD *kex;
	int burn_optimistic_kexinit:1;

	unsigned char *session_id;
#warning 64BIT: Inspect use of unsigned long
	unsigned long session_id_len;

	/* Server's public key */
	LIBSSH2_HOSTKEY_METHOD *hostkey;
	void *server_hostkey_abstract;

	/* Either set with libssh2_session_hostkey() (for server mode)
	 * Or read from server in (eg) KEXDH_INIT (for client mode)
	 */
	unsigned char *server_hostkey;
#warning 64BIT: Inspect use of unsigned long
	unsigned long server_hostkey_len;
#if LIBSSH2_MD5
	unsigned char server_hostkey_md5[MD5_DIGEST_LENGTH];
#endif /* ! LIBSSH2_MD5 */
	unsigned char server_hostkey_sha1[SHA_DIGEST_LENGTH];

	/* (remote as source of data -- packet_read ) */
	libssh2_endpoint_data remote;

	/* (local as source of data -- packet_write ) */
	libssh2_endpoint_data local;

	/* Inbound Data buffer -- Sometimes the packet that comes in isn't the packet we're ready for */
	LIBSSH2_PACKET_BRIGADE packets;

	/* Active connection channels */
	LIBSSH2_CHANNEL_BRIGADE channels;
#warning 64BIT: Inspect use of unsigned long
	unsigned long next_channel;

	LIBSSH2_LISTENER *listeners;

	/* Actual I/O socket */
	NSInteger socket_fd;
	NSInteger socket_block;
	NSInteger socket_state;

	/* Error tracking */
	char *err_msg;
#warning 64BIT: Inspect use of unsigned long
	unsigned long err_msglen;
	NSInteger err_should_free;
	NSInteger err_code;
};

/* session.state bits */
#define LIBSSH2_STATE_EXCHANGING_KEYS	0x00000001
#define LIBSSH2_STATE_NEWKEYS			0x00000002
#define LIBSSH2_STATE_AUTHENTICATED		0x00000004

/* session.flag helpers */
#ifdef MSG_NOSIGNAL
#define LIBSSH2_SOCKET_SEND_FLAGS(session)		(((session)->flags & LIBSSH2_FLAG_SIGPIPE) ? 0 : MSG_NOSIGNAL)
#define LIBSSH2_SOCKET_RECV_FLAGS(session)		(((session)->flags & LIBSSH2_FLAG_SIGPIPE) ? 0 : MSG_NOSIGNAL)
#else
/* If MSG_NOSIGNAL isn't defined we're SOL on blocking SIGPIPE */
#define LIBSSH2_SOCKET_SEND_FLAGS(session)		0
#define LIBSSH2_SOCKET_RECV_FLAGS(session)		0
#endif

/* libssh2 extensible ssh api, ultimately I'd like to allow loading additional methods via .so/.dll */

struct _LIBSSH2_KEX_METHOD {
	const char *name;

	/* Key exchange, populates session->* and returns 0 on success, non-0 on error */
	NSInteger (*exchange_keys)(LIBSSH2_SESSION *session);

#warning 64BIT: Inspect use of long
	long flags;
};

struct _LIBSSH2_HOSTKEY_METHOD {
	const char *name;
#warning 64BIT: Inspect use of unsigned long
	unsigned long hash_len;

#warning 64BIT: Inspect use of unsigned long
	NSInteger (*init)(LIBSSH2_SESSION *session, unsigned char *hostkey_data, unsigned long hostkey_data_len, void **abstract);
	NSInteger (*initPEM)(LIBSSH2_SESSION *session, const char *privkeyfile, unsigned const char *passphrase, void **abstract);
#warning 64BIT: Inspect use of unsigned long
#warning 64BIT: Inspect use of unsigned long
	NSInteger (*sig_verify)(LIBSSH2_SESSION *session, const unsigned char *sig, unsigned long sig_len, const unsigned char *m, unsigned long m_len, void **abstract);
#warning 64BIT: Inspect use of unsigned long
#warning 64BIT: Inspect use of unsigned long
	NSInteger (*signv)(LIBSSH2_SESSION *session, unsigned char **signature, unsigned long *signature_len, unsigned long veccount, const struct iovec datavec[], void **abstract);
#warning 64BIT: Inspect use of unsigned long
#warning 64BIT: Inspect use of unsigned long
	NSInteger (*encrypt)(LIBSSH2_SESSION *session, unsigned char **dst, unsigned long *dst_len, const unsigned char *src, unsigned long src_len, void **abstract);
	NSInteger (*dtor)(LIBSSH2_SESSION *session, void **abstract);
};

struct _LIBSSH2_CRYPT_METHOD {
	const char *name;

	NSInteger blocksize;

	/* iv and key sizes (-1 for variable length) */
	NSInteger iv_len;
	NSInteger secret_len;

#warning 64BIT: Inspect use of long
	long flags;

	NSInteger (*init)(LIBSSH2_SESSION *session, LIBSSH2_CRYPT_METHOD *method, unsigned char *iv, NSInteger *free_iv, unsigned char *secret, NSInteger *free_secret, NSInteger encrypt, void **abstract);
	NSInteger (*crypt)(LIBSSH2_SESSION *session, unsigned char *block, void **abstract);
	NSInteger (*dtor)(LIBSSH2_SESSION *session, void **abstract);

	_libssh2_cipher_type(algo);
};

struct _LIBSSH2_COMP_METHOD {
	const char *name;

	NSInteger (*init)(LIBSSH2_SESSION *session, NSInteger compress, void **abstract);
#warning 64BIT: Inspect use of unsigned long
#warning 64BIT: Inspect use of unsigned long
	NSInteger (*comp)(LIBSSH2_SESSION *session, NSInteger compress, unsigned char **dest, unsigned long *dest_len, unsigned long payload_limit, NSInteger *free_dest,
#warning 64BIT: Inspect use of unsigned long
												  const unsigned char *src, unsigned long src_len, void **abstract);
	NSInteger (*dtor)(LIBSSH2_SESSION *session, NSInteger compress, void **abstract);
};

struct _LIBSSH2_MAC_METHOD {
	const char *name;

	/* The length of a given MAC packet */
	NSInteger mac_len;

	/* integrity key length */
	NSInteger key_len;

	/* Message Authentication Code Hashing algo */
	NSInteger (*init)(LIBSSH2_SESSION *session, unsigned char *key, NSInteger *free_key, void **abstract);
#warning 64BIT: Inspect use of unsigned long
#warning 64BIT: Inspect use of unsigned long
#warning 64BIT: Inspect use of unsigned long
	NSInteger (*hash)(LIBSSH2_SESSION *session, unsigned char *buf, unsigned long seqno, const unsigned char *packet, unsigned long packet_len, const unsigned char *addtl, unsigned long addtl_len, void **abstract);
	NSInteger (*dtor)(LIBSSH2_SESSION *session, void **abstract);
};

#if defined(LIBSSH2_DEBUG_TRANSPORT) || defined(LIBSSH2_DEBUG_KEX) || defined(LIBSSH2_DEBUG_USERAUTH) || defined(LIBSSH2_DEBUG_CONNECTION) || defined(LIBSSH2_DEBUG_SCP) || defined(LIBSSH2_DEBUG_SFTP) || defined(LIBSSH2_DEBUG_ERRORS)
#define LIBSSH2_DEBUG_ENABLED

/* Internal debugging contexts -- Used with --enable-debug-* */
#define LIBSSH2_DBG_TRANS						1
#define LIBSSH2_DBG_KEX							2
#define LIBSSH2_DBG_AUTH						3
#define LIBSSH2_DBG_CONN						4
#define LIBSSH2_DBG_SCP							5
#define LIBSSH2_DBG_SFTP						6
#define LIBSSH2_DBG_ERROR						7
#define LIBSSH2_DBG_PUBLICKEY					8

void _libssh2_debug(LIBSSH2_SESSION *session, NSInteger context, const char *format, ...);

#endif /* LIBSSH2_DEBUG_ENABLED */

#ifdef LIBSSH2_DEBUG_ERRORS
#define libssh2_error(session, errcode, errmsg, should_free)	\
{ \
	if (session->err_msg && session->err_should_free) { \
		LIBSSH2_FREE(session, session->err_msg); \
	} \
	session->err_msg = errmsg; \
	session->err_msglen = strlen(errmsg); \
	session->err_should_free = should_free; \
	session->err_code = errcode; \
	_libssh2_debug(session, LIBSSH2_DBG_ERROR, "%d - %s", session->err_code, session->err_msg); \
}

#else /* ! LIBSSH2_DEBUG_ERRORS */

#define libssh2_error(session, errcode, errmsg, should_free)	\
{ \
	if (session->err_msg && session->err_should_free) { \
		LIBSSH2_FREE(session, session->err_msg); \
	} \
	session->err_msg = errmsg; \
	session->err_msglen = strlen(errmsg); \
	session->err_should_free = should_free; \
	session->err_code = errcode; \
}

#endif /* LIBSSH2_DEBUG_ENABLED */


#define LIBSSH2_SOCKET_UNKNOWN					 1
#define LIBSSH2_SOCKET_CONNECTED				 0
#define LIBSSH2_SOCKET_DISCONNECTED				-1

/* Initial packet state, prior to MAC check */
#define LIBSSH2_MAC_UNCONFIRMED					 1
/* When MAC type is "none" (proto initiation phase) all packets are deemed "confirmed" */
#define LIBSSH2_MAC_CONFIRMED					 0
/* Something very bad is going on */
#define LIBSSH2_MAC_INVALID						-1

/* SSH Packet Types -- Defined by internet draft */
/* Transport Layer */
#define SSH_MSG_DISCONNECT							1
#define SSH_MSG_IGNORE								2
#define SSH_MSG_UNIMPLEMENTED						3
#define SSH_MSG_DEBUG								4
#define SSH_MSG_SERVICE_REQUEST						5
#define SSH_MSG_SERVICE_ACCEPT						6

#define SSH_MSG_KEXINIT								20
#define SSH_MSG_NEWKEYS								21

/* diffie-hellman-group1-sha1 */
#define SSH_MSG_KEXDH_INIT							30
#define SSH_MSG_KEXDH_REPLY							31

/* diffie-hellman-group-exchange-sha1 */
#define SSH_MSG_KEX_DH_GEX_REQUEST_OLD				30
#define SSH_MSG_KEX_DH_GEX_REQUEST					34
#define SSH_MSG_KEX_DH_GEX_GROUP					31
#define SSH_MSG_KEX_DH_GEX_INIT						32
#define SSH_MSG_KEX_DH_GEX_REPLY					33

/* User Authentication */
#define SSH_MSG_USERAUTH_REQUEST					50
#define SSH_MSG_USERAUTH_FAILURE					51
#define SSH_MSG_USERAUTH_SUCCESS					52
#define SSH_MSG_USERAUTH_BANNER						53

/* "public key" method */
#define SSH_MSG_USERAUTH_PK_OK						60
/* "password" method */
#define SSH_MSG_USERAUTH_PASSWD_CHANGEREQ			60
/* "keyboard-interactive" method */
#define SSH_MSG_USERAUTH_INFO_REQUEST				60
#define SSH_MSG_USERAUTH_INFO_RESPONSE				61

/* Channels */
#define SSH_MSG_GLOBAL_REQUEST						80
#define SSH_MSG_REQUEST_SUCCESS						81
#define SSH_MSG_REQUEST_FAILURE						82

#define SSH_MSG_CHANNEL_OPEN						90
#define SSH_MSG_CHANNEL_OPEN_CONFIRMATION			91
#define SSH_MSG_CHANNEL_OPEN_FAILURE				92
#define SSH_MSG_CHANNEL_WINDOW_ADJUST				93
#define SSH_MSG_CHANNEL_DATA						94
#define SSH_MSG_CHANNEL_EXTENDED_DATA				95
#define SSH_MSG_CHANNEL_EOF							96
#define SSH_MSG_CHANNEL_CLOSE						97
#define SSH_MSG_CHANNEL_REQUEST						98
#define SSH_MSG_CHANNEL_SUCCESS						99
#define SSH_MSG_CHANNEL_FAILURE						100

void libssh2_session_shutdown(LIBSSH2_SESSION *session);

#warning 64BIT: Inspect use of unsigned long
unsigned long libssh2_ntohu32(const unsigned char *buf);
libssh2_uint64_t libssh2_ntohu64(const unsigned char *buf);
#warning 64BIT: Inspect use of unsigned long
void libssh2_htonu32(unsigned char *buf, unsigned long val);
void libssh2_htonu64(unsigned char *buf, libssh2_uint64_t val);

NSInteger libssh2_packet_read(LIBSSH2_SESSION *session, NSInteger block);
#warning 64BIT: Inspect use of unsigned long
#warning 64BIT: Inspect use of unsigned long
#warning 64BIT: Inspect use of unsigned long
NSInteger libssh2_packet_ask_ex(LIBSSH2_SESSION *session, unsigned char packet_type, unsigned char **data, unsigned long *data_len, unsigned long match_ofs, const unsigned char *match_buf, unsigned long match_len, NSInteger poll_socket);
#define libssh2_packet_ask(session, packet_type, data, data_len, poll_socket)	\
		libssh2_packet_ask_ex((session), (packet_type), (data), (data_len), 0, NULL, 0, (poll_socket))
#warning 64BIT: Inspect use of unsigned long
#warning 64BIT: Inspect use of unsigned long
#warning 64BIT: Inspect use of unsigned long
NSInteger libssh2_packet_askv_ex(LIBSSH2_SESSION *session, unsigned char *packet_types, unsigned char **data, unsigned long *data_len, unsigned long match_ofs, const unsigned char *match_buf, unsigned long match_len, NSInteger poll_socket);
#define libssh2_packet_askv(session, packet_types, data, data_len, poll_socket)	\
		libssh2_packet_askv_ex((session), (packet_types), (data), (data_len), 0, NULL, 0, (poll_socket))
#warning 64BIT: Inspect use of unsigned long
#warning 64BIT: Inspect use of unsigned long
#warning 64BIT: Inspect use of unsigned long
NSInteger libssh2_packet_require_ex(LIBSSH2_SESSION *session, unsigned char packet_type, unsigned char **data, unsigned long *data_len, unsigned long match_ofs, const unsigned char *match_buf, unsigned long match_len);
#define libssh2_packet_require(session, packet_type, data, data_len)			\
		libssh2_packet_require_ex((session), (packet_type), (data), (data_len), 0, NULL, 0)
#warning 64BIT: Inspect use of unsigned long
#warning 64BIT: Inspect use of unsigned long
#warning 64BIT: Inspect use of unsigned long
NSInteger libssh2_packet_requirev_ex(LIBSSH2_SESSION *session, unsigned char *packet_types, unsigned char **data, unsigned long *data_len, unsigned long match_ofs, const unsigned char *match_buf, unsigned long match_len);
#define libssh2_packet_requirev(session, packet_types, data, data_len)			\
		libssh2_packet_requirev_ex((session), (packet_types), (data), (data_len), 0, NULL, 0)
NSInteger libssh2_packet_burn(LIBSSH2_SESSION *session);
#warning 64BIT: Inspect use of unsigned long
NSInteger libssh2_packet_write(LIBSSH2_SESSION *session, unsigned char *data, unsigned long data_len);
NSInteger libssh2_kex_exchange(LIBSSH2_SESSION *session, NSInteger reexchange);
#warning 64BIT: Inspect use of unsigned long
unsigned long libssh2_channel_nextid(LIBSSH2_SESSION *session);
#warning 64BIT: Inspect use of unsigned long
LIBSSH2_CHANNEL *libssh2_channel_locate(LIBSSH2_SESSION *session, unsigned long channel_id);

/* Let crypt.c/hostkey.c/comp.c/mac.c expose their method structs */
LIBSSH2_CRYPT_METHOD **libssh2_crypt_methods(void);
LIBSSH2_HOSTKEY_METHOD **libssh2_hostkey_methods(void);
LIBSSH2_COMP_METHOD **libssh2_comp_methods(void);
LIBSSH2_MAC_METHOD **libssh2_mac_methods(void);

/* Language API doesn't exist yet.  Just act like we've agreed on a language */
#define libssh2_kex_agree_lang(session, endpoint, str, str_len)	0

/* pem.c */
NSInteger _libssh2_pem_parse (LIBSSH2_SESSION *session,
			const char *headerbegin,
			const char *headerend,
			FILE *fp,
			char **data, NSUInteger *datalen);
NSInteger _libssh2_pem_decode_sequence (unsigned char **data, NSUInteger *datalen);
NSInteger _libssh2_pem_decode_integer (unsigned char **data, NSUInteger *datalen,
				 unsigned char **i, NSUInteger *ilen);

#endif /* LIBSSH2_H */
