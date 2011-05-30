#include "mine.h"

void _set_sys_error(mine *self) {
	self->err  = errno;
	self->errstr = strerror(errno);
}

void _set_ssl_error(mine *self) {
	self->err = 0;
	self->errstr = ERR_lib_error_string( ERR_get_error() );
}

mine *mine_new() {
	mine *self = malloc(sizeof(mine));
	
	if (!self) {
		return self;
	}
	
	self->sock    = 0;
	self->ssl     = NULL;
	self->ctx     = NULL;
	self->err     = 0;
	self->errstr  = NULL;
	
	return self;
}

void mine_destroy(mine *self) {
	if (self->sock) {
		mine_disconnect(self);
	}
	
	free(self);
}

char mine_connect(mine *self, char *host, uint16_t port) {
	if (self->sock) {
		return 1;
	}
	
	int sock = 0;
	SSL *ssl = NULL;
	SSL_CTX *ctx = NULL;
	BIO *bio = NULL;
	
	sock = socket(PF_INET, SOCK_STREAM, 0);
	if (sock == -1) {
		goto MINE_CONNECT_ERROR_SYS;
	}
	
	struct hostent *hostinfo = gethostbyname(host);
	if (!hostinfo) {
		goto MINE_CONNECT_ERROR_SYS;
	}
	
	struct sockaddr_in dest;
	dest.sin_family = AF_INET;
	dest.sin_port = htons(port);
	dest.sin_addr = *(struct in_addr *) hostinfo->h_addr;
	
	if(connect(sock, (struct sockaddr *)&dest, sizeof(dest)) != 0) {
		goto MINE_CONNECT_ERROR_SYS;
	}
	
	char protocol;
	if (recv(sock, &protocol, 1, 0) != 1) {
		goto MINE_CONNECT_ERROR_SYS;
	}
	
	if (protocol == MINE_PROTO_SSL) {
		SSL_library_init();
		SSL_load_error_strings();
		
		ctx = SSL_CTX_new( SSLv23_method() );
		if (!ctx) { 
			goto MINE_CONNECT_ERROR_SSL;
		};
		
		ssl = SSL_new(ctx);
		if (!ssl) {
			goto MINE_CONNECT_ERROR_SSL;
		}
		
		bio = BIO_new_socket(sock, BIO_NOCLOSE);
		if (!bio) {
			goto MINE_CONNECT_ERROR_SSL;
		}
		
		SSL_set_bio(ssl, bio, bio);
		if (SSL_connect(ssl) <= 0) {
			goto MINE_CONNECT_ERROR_SSL;
		}
		
		self->ssl = ssl;
		self->ctx = ctx;
	}
	
	self->sock = sock;
	return 1;
	
	
	MINE_CONNECT_ERROR_SYS:
		_set_sys_error(self);
		goto MINE_CONNECT_ERROR;
	
	MINE_CONNECT_ERROR_SSL:
		_set_ssl_error(self);
		goto MINE_CONNECT_ERROR;
	
	MINE_CONNECT_ERROR:
		if (ctx) SSL_CTX_free(self->ctx);
		if (sock) close(sock);
		return 0;
}

char mine_disconnect(mine *self) {
	if (self->ssl) {
		SSL_CTX_free(self->ctx);
		self->ssl = NULL;
		self->ctx = NULL;
	}
	
	if (close(self->sock) == -1) {
		_set_sys_error(self);
		return 0;
	}
	
	return 1;
}
