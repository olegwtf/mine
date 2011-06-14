.PHONY: test

cc = gcc

all: lib test

lib:
	$(cc) -fPIC -c mine.c -g
	$(cc) -shared -o mine.so mine.o

test:
	$(cc) -o mtest test.c mine.so -lssl
	$(cc) -o mtest1 test1.c mine.so -lssl
clean:
	rm *.o *.so mtest*
