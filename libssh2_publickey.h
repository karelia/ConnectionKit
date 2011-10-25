/* Copyright (c) 2004-2006, Sara Golemon <sarag@libssh2.org>
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

/* Note: This include file is only needed for using the
 * publickey SUBSYSTEM which is not the same as publickey
 * authentication.  For authentication you only need libssh2.h
 *
 * For more information on the publickey subsystem,
 * refer to IETF draft: secsh-publickey
 */

#ifndef LIBSSH2_PUBLICKEY_H
#define LIBSSH2_PUBLICKEY_H	1

typedef struct _LIBSSH2_PUBLICKEY				LIBSSH2_PUBLICKEY;

typedef struct _libssh2_publickey_attribute {
	char *name;
#warning 64BIT: Inspect use of unsigned long
	unsigned long name_len;
	char *value;
#warning 64BIT: Inspect use of unsigned long
	unsigned long value_len;
	char mandatory;
} libssh2_publickey_attribute;

typedef struct _libssh2_publickey_list {
	unsigned char *packet; /* For freeing */

	unsigned char *name;
#warning 64BIT: Inspect use of unsigned long
	unsigned long name_len;
	unsigned char *blob;
#warning 64BIT: Inspect use of unsigned long
	unsigned long blob_len;
#warning 64BIT: Inspect use of unsigned long
	unsigned long num_attrs;
	libssh2_publickey_attribute *attrs; /* free me */
} libssh2_publickey_list;

/* Generally use the first macro here, but if both name and value are string literals, you can use _fast() to take advantage of preprocessing */
#define libssh2_publickey_attribute(name, value, mandatory) 		{ (name), strlen(name), (value), strlen(value), (mandatory) },
#warning 64BIT: Inspect use of sizeof
#warning 64BIT: Inspect use of sizeof
#define libssh2_publickey_attribute_fast(name, value, mandatory)	{ (name), sizeof(name) - 1, (value), sizeof(value) - 1, (mandatory) },

#ifdef __cplusplus
extern "C" {
#endif

/* Publickey Subsystem */
LIBSSH2_API LIBSSH2_PUBLICKEY *libssh2_publickey_init(LIBSSH2_SESSION *session);

#warning 64BIT: Inspect use of unsigned long
LIBSSH2_API NSInteger libssh2_publickey_add_ex(LIBSSH2_PUBLICKEY *pkey, const unsigned char *name, unsigned long name_len,
#warning 64BIT: Inspect use of unsigned long
															const unsigned char *blob, unsigned long blob_len, char overwrite,
#warning 64BIT: Inspect use of unsigned long
															unsigned long num_attrs, libssh2_publickey_attribute attrs[]);
#define libssh2_publickey_add(pkey, name, blob, blob_len, overwrite, num_attrs, attrs) \
		libssh2_publickey_add_ex((pkey), (name), strlen(name), (blob), (blob_len), (overwrite), (num_attrs), (attrs))

#warning 64BIT: Inspect use of unsigned long
LIBSSH2_API NSInteger libssh2_publickey_remove_ex(LIBSSH2_PUBLICKEY *pkey, const unsigned char *name, unsigned long name_len,
#warning 64BIT: Inspect use of unsigned long
															const unsigned char *blob, unsigned long blob_len);
#define libssh2_publickey_remove(pkey, name, blob, blob_len) \
		libssh2_publickey_remove_ex((pkey), (name), strlen(name), (blob), (blob_len))

#warning 64BIT: Inspect use of unsigned long
LIBSSH2_API NSInteger libssh2_publickey_list_fetch(LIBSSH2_PUBLICKEY *pkey, unsigned long *num_keys, libssh2_publickey_list **pkey_list);
LIBSSH2_API void libssh2_publickey_list_free(LIBSSH2_PUBLICKEY *pkey, libssh2_publickey_list *pkey_list);

LIBSSH2_API void libssh2_publickey_shutdown(LIBSSH2_PUBLICKEY *pkey);

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* ndef: LIBSSH2_PUBLICKEY_H */
