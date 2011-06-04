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

#define MINE_PROTO_PLAIN     0
#define MINE_PROTO_SSL       1
#define MINE_LOGIN_FAIL      0
#define MINE_LOGIN_OK        1
#define MINE_PROTO_AUTH      1
#define MINE_PROTO_EVENT_REG 3
#define MINE_PROTO_EVENT_SND 2
#define MINE_PROTO_DATA      0

char MINE_SSL_LOADED = 0;

typedef struct mine {
	int sock;
	SSL *ssl;
	SSL_CTX *ctx;
	int err;
	const char *errstr;
	char *snd_event;
	char *rcv_event;
	uint64_t snd_datalen;
	uint64_t rcv_datalen;
} mine;

mine *mine_new();
void mine_destroy(mine *self);
char mine_connect(mine *self, char *host, uint16_t port);
char mine_disconnect(mine *self);
char mine_login(mine *self, char *login, char *password);
char mine_event_reg(mine *self, char *event, char *ip);
char mine_event_send(mine *self, char *event, uint64_t datalen, char *data);
uint64_t mine_event_recv(mine *self, char *event, char *buf);

#endif // MINE_H
