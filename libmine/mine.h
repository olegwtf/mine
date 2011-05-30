#ifndef MINE_H
#define MINE_H

#include <stdlib.h>
#include <stdint.h>
#include <errno.h>
#include <string.h>
#include <openssl/ssl.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netdb.h>
#include <arpa/inet.h>
#include <openssl/bio.h>
#include <openssl/err.h>

#define MINE_PROTO_PLAIN 0
#define MINE_PROTO_SSL   1

typedef struct mine {
	int sock;
	SSL *ssl;
	SSL_CTX *ctx;
	int err;
	const char *errstr;
} mine;

mine *mine_new();
void mine_destroy(mine *self);
char mine_connect(mine *self, char *host, uint16_t port);
char mine_disconnect(mine *self);
// char mine_login(mconn conn, char *login, char *password);
// char mine_event_reg(mconn conn, char *event, char *ip);
// char mine_event_send(mconn conn, char *event, char *data);
// char *mine_event_read(mconn conn);


#endif // MINE_H