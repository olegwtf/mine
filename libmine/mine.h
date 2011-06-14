#ifndef MINE_H
#define MINE_H

#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <errno.h>
#include <openssl/ssl.h>
#include <openssl/bio.h>
#include <openssl/err.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netdb.h>
#include <arpa/inet.h>

#define MINE_PROTO_PLAIN        0
#define MINE_PROTO_SSL          1
#define MINE_PROTO_DATA_RCV     0
#define MINE_PROTO_DATA_SND     0
#define MINE_PROTO_AUTH         1
#define MINE_PROTO_EVENT_RCV    2
#define MINE_PROTO_EVENT_SND    2
#define MINE_PROTO_EVENT_REG    3
#define MINE_PROTO_WAITING      4
#define MINE_PROTO_AUTH_SUCCESS 0
#define MINE_PROTO_AUTH_FAIL    0

#define MINE_CHUNK_SIZE      1024

char MINE_SSL_LOADED = 0;

typedef struct {
	int sock;
	SSL *ssl;
	SSL_CTX *ctx;
	int err;
	const char *errstr;
	char *snd_event;
	char *rcv_event;
	int64_t snd_datalen;
	int64_t rcv_datalen;
	int64_t cur_datalen;
	char readed;
} MINE;

MINE *mine_new();
void mine_destroy(MINE *self);
char mine_connect(MINE *self, char *host, uint16_t port);
char mine_disconnect(MINE *self);
char mine_login(MINE *self, char *login, char *password);
char mine_event_reg(MINE *self, char *event, char *ip);
char mine_event_send(MINE *self, char *event, int64_t datalen, int chunklen, char *data);
int mine_event_recv(MINE *self, char **event, int64_t *datalen, char *buf);

#endif // MINE_H
