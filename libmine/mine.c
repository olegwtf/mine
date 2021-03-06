#include "mine.h"

void _mine_set_sys_error(MINE *self) {
	self->err  = errno;
	self->errstr = strerror(errno);
	if (self->errstr == NULL) {
		self->errstr = "All ok";
	}
}

void _mine_set_ssl_error(MINE *self) {
	self->err = 0;
	self->errstr = ERR_lib_error_string( ERR_get_error() );
	if (self->errstr == NULL) {
		self->errstr = "All ok";
	}
}

void _mine_set_error(MINE *self) {
	if (self->ssl) {
		_mine_set_ssl_error(self);
	}
	else {
		_mine_set_sys_error(self);
	}
}

int _mine_write(MINE *self, const void *msg, size_t len) {
	if (self->ssl) {
		return SSL_write(self->ssl, msg, len);
	}
	
	return send(self->sock, msg, len, MSG_NOSIGNAL);
}

int _mine_read(MINE *self, void *buf, size_t len) {
	if (self->ssl) {
		return SSL_read(self->ssl, buf, len);
	}
	
	return recv(self->sock, buf, len, 0);
}

MINE *mine_new() {
	MINE *self = malloc(sizeof(MINE));
	
	if (!self) {
		return self;
	}
	
	self->sock        = 0;
	self->ssl         = NULL;
	self->ctx         = NULL;
	self->err         = 0;
	self->errstr      = NULL;
	self->snd_event   = NULL;
	self->rcv_event   = NULL;
	self->snd_datalen = 0;
	self->rcv_datalen = 0;
	self->cur_datalen = 0;
	self->readed      = 0;
	
	return self;
}

void mine_destroy(MINE *self) {
	if (self->sock) {
		mine_disconnect(self);
	}
	
	free(self);
}

char mine_connect(MINE *self, char *host, uint16_t port) {
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

char mine_disconnect(MINE *self) {
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

char mine_login(MINE *self, char *login, char *password) {
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
	
	if (login_status == MINE_PROTO_AUTH_FAIL) {
		self->err = 0;
		self->errstr = "Login failed";
		return 0;
	}
	
	return 1;
}

char mine_event_reg(MINE *self, char *event, char *ip) {
	unsigned char event_len = strlen(event);
	
	struct in_addr addr;
	if (!inet_aton(ip, &addr)) {
		_mine_set_sys_error(self);
		return 0;
	}
	
	int msg_len = event_len+6;
	char buf[msg_len];
	sprintf(buf, "%c%c%s", MINE_PROTO_EVENT_REG, event_len, event);
	memcpy(buf+event_len+2, &(addr.s_addr), 4);
	if (_mine_write(self, buf, msg_len) <= 0) {
		_mine_set_error(self);
		return 0;
	}
	
	return 1;
}

char mine_event_send(MINE *self, char *event, int64_t datalen, int chunklen, char *data) {
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
		sprintf(buf, "%c%c%s", MINE_PROTO_EVENT_SND, event_len, event);
		if (_mine_write(self, buf, msg_len) <= 0) {
			_mine_set_error(self);
			return 0;
		}
	}
	
	if (self->snd_datalen == 0) {
		self->snd_datalen = datalen;
		char buf[9];
		sprintf(buf, "%c", MINE_PROTO_DATA_SND);
		memcpy(buf+1, &datalen, 8);
		if (_mine_write(self, buf, 9) <= 0) {
			_mine_set_error(self);
			return 0;
		}
	}
	
	if (_mine_write(self, data, chunklen) <= 0) {
		_mine_set_error(self);
		return 0;
	}
	
	self->snd_datalen -= chunklen;
	return 1;
}

int mine_event_recv(MINE *self, char **event, int64_t *datalen, char *buf) {
	if (self->rcv_datalen == 0 && self->readed) {
		self->readed = 0;
		self->cur_datalen = 0;
		return -2;
	}
	
	int readed = 0;
	bzero(buf, MINE_CHUNK_SIZE);
	
	if (self->rcv_datalen == 0) {
		char proto_op;
		if (_mine_read(self, &proto_op, 1) <= 0) {
			_mine_set_error(self);
			return -1;
		}
		
		if (proto_op == MINE_PROTO_EVENT_RCV) {
			char ev_len;
			if (_mine_read(self, &ev_len, 1) <= 0) {
				_mine_set_error(self);
				return -1;
			}
			
			*event = malloc(ev_len+1);
			if (!*event) {
				_mine_set_sys_error(self);
				return -1;
			}
			
			bzero(*event, ev_len+1);
			if (_mine_read(self, *event, ev_len) < ev_len) {
				_mine_set_error(self);
				return -1;
			}
			
			if (self->rcv_event) {
				free(self->rcv_event);
			}
			self->rcv_event = *event;
			
			if (_mine_read(self, &proto_op, 1) <= 0) {
				_mine_set_error(self);
				return -1;
			}
		}
		
		if (proto_op == MINE_PROTO_DATA_RCV) {
			if (_mine_read(self, &(self->rcv_datalen), 8) <= 0) {
				_mine_set_error(self);
				return -1;
			}
			
			self->cur_datalen = self->rcv_datalen;
		}
		else {
			self->err = 0;
			self->errstr = "Unexpected protocol operation received";
			return -1;
		}
	}
	
	if (self->rcv_datalen) {
		readed = _mine_read(self, buf, self->rcv_datalen > MINE_CHUNK_SIZE-1 ? MINE_CHUNK_SIZE-1 : self->rcv_datalen);
		if (readed <= 0) {
			_mine_set_error(self);
			return -1;
		}
		
		self->rcv_datalen -= readed;
	}
	
	if (self->rcv_datalen == 0) {
		self->readed = 1;
	}
	
	if (!self->rcv_event) {
		self->err = 0;
		self->errstr = "Data received before event";
		return -1;
	}
	
	*datalen = self->cur_datalen;
	*event = self->rcv_event;
	return readed;
}
