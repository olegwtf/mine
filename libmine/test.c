#include <stdio.h>
#include "mine.h"

int main() {
	mine *m = mine_new();
	
	if (mine_connect(m, "localhost", 1135)) {
		printf("Successfully connected. %s protocol\n", m->ssl ? "SSL" : "Plain");
		mine_disconnect(m);
	}
	else {
		printf("Connection error: %s\n", m->errstr);
	}
	
	mine_destroy(m);
	
	return 0;
}
