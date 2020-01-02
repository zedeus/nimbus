#ifndef __LIBNIMBUS_H__
#define __LIBNIMBUS_H__

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/** Buffer lengths, can be used in go for convenience */
#define TOPIC_LEN 4
#define ID_LEN 32
#define SYMKEY_LEN 32
#define PRIVKEY_LEN 32
#define BLOOM_LEN 64
#define ADDRESS_LEN 20
#define URL_LEN 256
// EXTKEY_LEN is the length of a serialized public or private
// extended key.  It consists of 4 bytes version, 1 byte depth, 4 bytes
// fingerprint, 4 bytes child number, 32 bytes chain code, and 33 bytes
// public/private key data.
#define EXTKEY_LEN (4 + 1 + 4 + 4 + 32 + 33) // 78 bytes

typedef struct {
  const uint8_t* decoded; /* Decoded payload */
  size_t decodedLen;  /* Decoded payload length */
  const uint8_t* source; /* 64 bytes public key, can be nil */
  const uint8_t* recipientPublicKey; /* 64 bytes public key, can be nil */
  uint32_t timestamp; /* Timestamp of creation message, expiry - ttl  */
  uint32_t ttl; /* TTL of message */
  uint8_t topic[TOPIC_LEN]; /* Topic of message */
  double pow; /* PoW value of received message */
  uint8_t hash[ID_LEN]; /* Hash of message */
} received_message;

typedef struct {
  const uint8_t* symKeyID; /* 32 bytes identifier for symmetric key, set to nil if none */
  const uint8_t* privateKeyID; /* 32 bytes identifier for asymmetric key, set to nil if none */
  const uint8_t* source; /* 64 bytes public key, set to nil if none */
  double minPow; /* Minimum PoW that message must have */
  uint8_t topic[TOPIC_LEN]; /* Will default to 0x00000000 if not provided */
  int allowP2P;
} filter_options;

typedef struct {
  const uint8_t* symKeyID; /* 32 bytes identifier for symmetric key, set to nil if none */
  const uint8_t* pubKey; /* 64 bytes public key, set to nil if none */
  const uint8_t* sourceID; /* 32 bytes identifier for asymmetric key, set to nil if none */
  uint32_t ttl; /* TTL of message */
  uint8_t topic[TOPIC_LEN]; /* Will default to 0x00000000 if not provided */
  uint8_t* payload; /* Payload to be send, can be len=0 but can not be nil */
  size_t payloadLen; /* Payload length */
  uint8_t* padding; /* Custom padding, can be set to nil */
  size_t paddingLen; /* Padding length */
  double powTime; /* Maximum time to calculate PoW */
  double powTarget; /* Minimum PoW target to reach before stopping */
} post_message;

typedef struct {
  uint8_t topic[TOPIC_LEN];
} topic;

typedef struct {
  uint8_t address[ADDRESS_LEN];
  char url[URL_LEN];
} account;

typedef struct {
  char id[ID_LEN];
  uint8_t address[ADDRESS_LEN];
  uint8_t privateKeyID[PRIVKEY_LEN]; /* 32 bytes identifier for asymmetric key, set to nil if none */
  uint8_t extKey[EXTKEY_LEN];
} key;

typedef void (*received_msg_handler)(received_message* msg, void* udata);

/** Initialize Nim and the Status library. Must be called before anything else
 * of the API. Also, all following calls must come from the same thread as from
 * which this call was done.
 */
void NimMain();

/** Start Ethereum node with Whisper capability and connect to Status fleet.
 * Optionally start discovery and listen for incoming connections.
 * The minPow value is the minimum required PoW that this node will allow.
 * When privkey is null, a new keypair will be generated.
 */
bool nimbus_start(uint16_t port, bool startListening, bool enableDiscovery,
  double minPow, const uint8_t* privkey, bool staging);

/** Add peers to connect to - must be called after nimbus_start */
bool nimbus_add_peer(const char* nodeId);

/**
 * Should be called in regularly - for example in a busy loop (beautiful!) on
 * dedicated thread.
 */
void nimbus_poll();

/** Asymmetric Keys API */

/** Raw 32 byte arrays are passed as IDs. The caller needs to provide a pointer
 * to 32 bytes allocation for this. */
bool nimbus_new_keypair(uint8_t id[ID_LEN]);
bool nimbus_add_keypair(const uint8_t privkey[PRIVKEY_LEN], uint8_t id[ID_LEN]);
bool nimbus_delete_keypair(const uint8_t id[ID_LEN]);
bool nimbus_delete_keypairs();
bool nimbus_get_private_key(const uint8_t id[ID_LEN],
  uint8_t privkey[PRIVKEY_LEN]);

/** Symmetric Keys API */

/** Raw 32 byte arrays are passed as IDs. The caller needs to provide a pointer
 * to 32 bytes allocation for this. */
bool nimbus_add_symkey(const uint8_t symkey[SYMKEY_LEN], uint8_t id[ID_LEN]);
bool nimbus_add_symkey_from_password(const char* password, uint8_t id[ID_LEN]);
bool nimbus_delete_symkey(const uint8_t id[ID_LEN]);
bool nimbus_get_symkey(const uint8_t id[ID_LEN], uint8_t symkey[SYMKEY_LEN]);

/** Whisper message posting and receiving API */

/* Post Whisper message to the queue */
bool nimbus_post(post_message* msg);
/** Subscribe to given filter. The void pointer udata will be passed to the
 * received_msg_handler callback.
 */
bool nimbus_subscribe_filter(filter_options* filter_options,
  received_msg_handler msg, void* udata, uint8_t id[ID_LEN]);
bool nimbus_unsubscribe_filter(const uint8_t id[ID_LEN]);

/** Get the minimum required PoW of this node */
double nimbus_get_min_pow();

/** Get the currently set bloom filter of this node. This will automatically
 *update for each filter subsribed to.
 */
void nimbus_get_bloom_filter(uint8_t bloomfilter[BLOOM_LEN]);

/** Example helper, can be removed */
topic nimbus_channel_to_topic(const char* channel);

/** Very limited Status chat API */

void nimbus_post_public(const char* channel, const char* payload);
void nimbus_join_public_chat(const char* channel, received_msg_handler msg);

/** Key store API */
bool nimbus_keystore_import_ecdsa(const uint8_t privkey[PRIVKEY_LEN], const char* passphrase, account* acc);
bool nimbus_keystore_import_single_extendedkey(const char* extKeyJSON, const char* passphrase, account* acc);
bool nimbus_keystore_import_extendedkeyforpurpose(int purpose, const char* extKeyJSON, const char* passphrase, account* acc);
bool nimbus_keystore_account_decrypted_key(const char* auth, account* acc, key* k);
bool nimbus_keystore_delete(const account* acc, const char* auth);

#ifdef __cplusplus
}
#endif

#endif //__LIBNIMBUS_H__
