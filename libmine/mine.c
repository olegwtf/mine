#include "mine.h"

void _mine_set_sys_error(mine *self) {
	self->err  = errno;
	self->errstr = strerror(errno);
}

void _mine_set_ssl_error(mine *self) {
	self->err = 0;
	self->errstr = ERR_lib_error_string( ERR_get_error() );
}

void _mine_set_error(mine *self) {
	if (self->ssl) {
		_mine_set_ssl_error(self);
	}
	else {
		_mine_set_sys_error(self);
	}
}

int _mine_write(mine *self, const void *msg, size_t len) {
	if (self->ssl) {
		return SSL_write(self->ssl, msg, len);
	}
	
	return send(self->sock, msg, len, MSG_NOSIGNAL);
}

int _mine_read(mine *self, void *buf, size_t len) {
	if (self->ssl) {
		return SSL_read(self->ssl, buf, len);
	}
	
	return recv(self->sock, buf, len, 0);
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
	self->snd_event   = NULL;
	self->snd_datalen = 0;
	self->rcv_datalen = 0;
	
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
		if (!MINE_SSL_LOADED) {
			SSL_library_init();
			SSL_load_error_strings();
			MINE_SSL_LOADED = 1;
		}
		
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
		_mine_set_sys_error(self);
		goto MINE_CONNECT_ERROR;
	
	MINE_CONNECT_ERROR_SSL:
		_mine_set_ssl_error(self);
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
		_mine_set_sys_error(self);
		return 0;
	}
	
	return 1;
}

char mine_login(mine *self, char *login, char *password) {
	unsigned char login_len = login ? strlen(login) : 0;
	unsigned char password_len = password ? strlen(password) : 0;
	
	int msg_len = login_len+password_len+2;
	char buf[msg_len];
	sprintf(buf, "%c%s%c%s", login_len, login ? login : "", password_len, password ? password : "");
	if (_mine_write(self, buf, msg_len) <= 0) {
		_mine_set_error(self);
		return 0;
	}
	
	char login_status;
	if (_mine_read(self, &login_status, 1) <= 0) {
		_mine_set_error(self);
		return 0;
	}
	
	if (login_status == MINE_LOGIN_FAIL) {
		self->err = 0;
		self->errstr = "Login failed";
		return 0;
	}
	
	return 1;
}

char mine_event_reg(mine *self, char *event, char *ip) {
	unsigned char event_len = strlen(event);
	
	struct in_addr addr;
	if (!inet_aton(ip, &addr)) {
		_mine_set_sys_error(self);
		return 0;
	}
	
	int msg_len = event_len+6;
	char buf[msg_len];
	sprintf(buf, "%c%c%s", MINE_MAGIC_EVENT_REG, event_len, event);
	memcpy(buf+event_len+2, &(addr.s_addr), 4);
	if (_mine_write(self, buf, msg_len) <= 0) {
		_mine_set_error(self);
		return 0;
	}
	
	return 1;
}

char mine_event_send(mine *self, char *event, uint64_t datalen, char *data) {
	if (self->snd_event == NULL || strcmp(event, self->snd_event) != 0) {
		if (self->snd_datalen != 0) {
			self->err = 0;
			self->errstr = "Incomplete data remain from previous event";
			return 0;
		}
		
		if (self->snd_event != NULL) {
			free(self->snd_event);
		}
		self->snd_event = strdup(event);
		int event_len = strlen(event);
		int msg_len = event_len + 2;
		char buf[msg_len];
		sprintf(buf, "%c%c%s", MINE_MAGIC_EVENT_SND, event_len, event);
		if (_mine_write(self, buf, msg_len) <= 0) {
			_mine_set_error(self);
			return 0;
		}
	}
	
	if (self->snd_datalen == 0) {
		self->snd_datalen = datalen;
		char buf[9];
		sprintf(buf, "%c", MINE_MAGIC_DATA);
		memcpy(buf+1, &datalen, 8);
		if (_mine_write(self, buf, 9) <= 0) {
			_mine_set_error(self);
			return 0;
		}
	}
	
	uint64_t chunklen = strlen(data);
	if (_mine_write(self, data, chunklen) <= 0) {
		_mine_set_error(self);
		return 0;
	}
	
	self->snd_datalen -= chunklen;
	return 1;
}

uint64_t mine_event_recv(mine *self, char *event, char *buf) {
	
}
