#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"
#include "../../mine.h"

typedef struct {
	MINE* mine;
	char autodie;
} MINE_LIB;

#define P_TO_MINE_LIB(object, context) p_to_mine_lib(aTHX_ object, context)

static MINE_LIB* p_to_mine_lib(pTHX_ SV *object, const char *context) {
	SV *sv;
	IV address;
	
	SvGETMAGIC(object);
	if (!SvROK(object)) {
		if (SvOK(object)) croak("%s is not a reference", context);
		croak("%s is undefined", context);
	}
	sv = SvRV(object);
	if (!SvOBJECT(sv)) croak("%s is not an object reference", context);
	
	address = SvIV(sv);
	if (!address)
		croak("Mine::Lib object %s has a NULL pointer", context);
	return INT2PTR(MINE_LIB*, address);
}

MODULE = Mine::Lib		PACKAGE = Mine::Lib		

SV*
new(char* class, ...)
	PREINIT:
		MINE_LIB *self;
		I32 i;
	CODE:
		if (items % 2 == 0) croak("Odd number of elements in options");
		
		Newx(self, 1, MINE_LIB);
		self->mine = mine_new();
		self->autodie = 0;
		for (i=1; i<items; i+=2) {
			if (strEQ( SvPV_nolen(ST(i)), "autodie" )) {
				self->autodie = SvIV(ST(i+1));
			}
			// other options here
			else {
				croak("Unsupported option: %s", SvPV_nolen(ST(i)));
			}
		}
		
		RETVAL = sv_newmortal();
		sv_setref_pv(RETVAL, class, (void *)self);
		SvREFCNT_inc(RETVAL);
	OUTPUT:
		RETVAL

void
DESTROY(MINE_LIB *self)
	CODE:
		mine_destroy(self->mine);
		SvREFCNT_dec(self);
		Safefree(self);

int
connect(MINE_LIB *self, char *host, int port)
	CODE:
		RETVAL = mine_connect(self->mine, host, port);
		if (RETVAL == 0 && self->autodie) {
			croak(self->mine->errstr);
		}
	OUTPUT:
		RETVAL

int
disconnect(MINE_LIB *self)
	CODE:
		RETVAL = mine_disconnect(self->mine);
		if (RETVAL == 0 && self->autodie) {
			croak(self->mine->errstr);
		}
	OUTPUT:
		RETVAL

int
login(MINE_LIB *self, char *login, char *password)
	CODE:
		RETVAL = mine_login(self->mine, login, password);
		if (RETVAL == 0 && self->autodie) {
			croak(self->mine->errstr);
		}
	OUTPUT:
		RETVAL

int
event_reg(MINE_LIB *self, char *event, char *ip)
	CODE:
		RETVAL = mine_event_reg(self->mine, event, ip);
		if (RETVAL == 0 && self->autodie) {
			croak(self->mine->errstr);
		}
	OUTPUT:
		RETVAL

int
event_send(MINE_LIB *self, char *event, int datalen, SV *data)
	CODE:
		STRLEN chunk_len;
		char *data_ptr = SvPV(data, chunk_len);
		RETVAL = mine_event_send(self->mine, event, datalen, chunk_len, data_ptr);
		if (RETVAL == 0 && self->autodie) {
			croak(self->mine->errstr);
		}
	OUTPUT:
		RETVAL

int
event_recv(MINE_LIB *self, SV *event, SV *datalen, SV *buf)
	INIT:
		if (!SvROK(event))
			croak("event should be a reference to scalar");
		
		if (!SvROK(datalen))
			croak("datalen should be a reference to scalar");
		
		if (!SvROK(buf))
			croak("buf should be a reference to scalar");
		
		char *ev, bf[MINE_CHUNK_SIZE];
		int64_t dlen;
	CODE:
		RETVAL = mine_event_recv(self->mine, &ev, &dlen, bf);
		if (RETVAL >= 0) {
			sv_setpv_mg(SvRV(event), ev);
			sv_setiv_mg(SvRV(datalen), dlen);
			sv_setpv_mg(SvRV(buf), bf);
		}
		
		if (RETVAL == -1 && self->autodie) {
			croak(self->mine->errstr);
		}
	OUTPUT:
		RETVAL
