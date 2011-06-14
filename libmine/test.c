#include <stdio.h>
#include "mine.h"

int main() {
	MINE *m = mine_new();
	
	if (mine_connect(m, "localhost", 1135)) {
		printf("Successfully connected. %s protocol\n", m->ssl ? "SSL" : "Plain");
		if (mine_login(m, "root", "toor")) {
			printf("Successfully logged in\n");
			
			if (mine_event_reg(m, "EV_COME", "0.0.0.0")) {
				printf("Event successfully registered\n");
				
				if (mine_event_send(m, "EV_SUX", 10, 10, "abcdefghij")) {
					printf("Event successfully sent\n");
				}
				else {
					printf("Error while sending event: %s\n", m->errstr);
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
