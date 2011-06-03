#include <stdio.h>
#include "mine.h"

int main() {
	mine *m = mine_new();
	
	if (mine_connect(m, "localhost", 1135)) {
		printf("Successfully connected. %s protocol\n", m->ssl ? "SSL" : "Plain");
		if (mine_login(m, "root", "toor")) {
			printf("Successfully logged in\n");
			
			if (mine_event_reg(m, "EV_COME", "0.0.0.0")) {
				printf("Event successfully registered\n");
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
