##
# Project Title
#
# @file
# @version 0.1

clean:
	rm -f *.o
	rm -rf build/*

rom: build/ralsei.nes

build/ralsei.nes: ralsei.s *.bin
	cl65 ralsei.s --verbose --target nes -o $@

run: build/ralsei.nes
	fceux $^



# end
