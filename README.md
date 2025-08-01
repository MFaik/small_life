# small life
Minimal implementation of Conway's Game of Life in x86_64 assembly.
The program can be run on a barebones linux tty. 
Due to the nature of the way syscalls are used, if there is any problem on your machine, feel free to open a new issue, or if you have a great way to make the binary smaller also feel free to open a new issue. 
## usage
Only NASM is needed for the compilation process. To compile the program just run,
```
./compiler game
```
and you would be good to go.

You can provide an initial setup for the program by giving the initial setup as an argument. The format of the argument is,
```
1  -> set
   -> not set (space character)
\n -> new line characters acts as a newline
```
and here is example uses,
```bash
# the all time classic, glider
./game "
1 
 1 
111"
# or alternatively you can use the provided example file
./game "$(cat 119P4H1V0)" # on bash
./game (cat 119P4H1V0 | string collect) # on fish
```
Improtant note, remember that if you are using a window manager, they would be interfering with the rendering. Thus this only works on a tty. Just press ctrl+alt+f5 or google it or something.
