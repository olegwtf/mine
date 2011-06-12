#include <stdio.h>
#include "mine.h"

int main() {
	mine *m = mine_new();
	
	if (mine_connect(m, "localhost", 1135)) {
		printf("Successfully connected. %s protocol\n", m->ssl ? "SSL" : "Plain");
		if (mine_login(m, "oleg", "qwer")) {
			printf("Successfully logged in\n");
			
			if (mine_event_reg(m, "EV_SUX", "0.0.0.0")) {
				printf("Event successfully registered\n");
				
				char *event;
				char data[MINE_CHUNK_SIZE];
				int64_t rv;
				while (1) {
					while ((rv = mine_event_recv(m, &event, data)) >= 0) {
						printf("%ld, %s, %s\n", rv, event, data);
					}
					
					if (rv == -1) {
						if(m->errstr != NULL) printf("%s\n", m->errstr);
						break;
					}
				}
			}
			else {
				printf("Event registration error: %s\n", m->errstr);
			}
		}
		else {
			printf("Login error: %s\n", m->errstr);
		}
		mine_disconnect(m);
	}
	else {
		printf("Connection error: %s\n", m->errstr);
	}
	
	mine_destroy(m);
	
	return 0;
}
