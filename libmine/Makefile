cc = gcc

all: lib test

lib:
	$(cc) -fPIC -c mine.c
	$(cc) -shared -o mine.so mine.o

test:
	$(cc) -o mtest test.c mine.so -lssl

clean:
	rm *.o *.so mtest
