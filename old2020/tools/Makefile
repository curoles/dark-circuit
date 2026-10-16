.PHONY: all clean
all: as

ISA := $(SRC)/../isa

as:  $(SRC)/as.cpp $(ISA)/isa.cpp $(ISA)/isa.h $(ISA)/isa-define.h
	g++ -O3 -Wall -Werror -lstdc++ -I$(SRC)/.. $(SRC)/as.cpp $(ISA)/isa.cpp -o as

clean:
	rm ./as
