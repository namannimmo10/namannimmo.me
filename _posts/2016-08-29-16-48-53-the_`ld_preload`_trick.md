---
layout:		post
title:		The LD_PRELOAD trick
summary:	Using LD_PRELOAD and the dynamic linker for hidden code injection.
date:		2016-08-29 16-48-53
categories:	c low-level kernel
---

I recently worked on an exciting system-level C library,
[tssx](https://github.com/goldsborough/tssx), at the Chair for Database systems
at TUM that transparently replaces any executable's domain socket communication
with a fast shared memory channel. With our library, Postgres runs more than twice as fast, while some programs can even be sped up by an order of
magnitude. At the core of this library lies the `LD_PRELOAD` trick, which I will touch upon in this article.

## Outline

- [Introduction](#introduction)
- [Code Injection](#code-injection)
	- [OS X](#os-x)
- [Symbol Fishing](#symbol-fishing)
- [Outro](#outro)

## Introduction

The `LD_PRELOAD` trick exploits functionality provided by the dynamic linker on
Unix systems that allows you to tell the linker to bind symbols provided by a
certain shared library *before other libraries*. For this, remember that upon
program execution, the operating system's *dynamic loader* will first load
dynamic libraries you link to into the process's memory (address space), such
that the *dynamic linker* can then resolve symbols at load or run time and bind
them to actual definitions. You can find more on this
[here](http://stackoverflow.com/questions/10052464/difference-between-dynamic-loading-and-dynamic-linking). Also, just to make the terminology clear, with a *symbol* I mean any function,
structure or variable declaration a program can reference in code. In this
article, we will be primarily dealing with function symbols. The following paragraphs will dive deeper into the `LD_PRELOAD` trick and give you some practical examples of how to use it on Linux and OS X.

## Code Injection

As mentioned above, the linker is responsible for resolving symbol references to
their actual definitions. Things get fun once we understand that we can, in fact, provide
more than one definition for a certain symbol. We'll have to navigate these
waters carefully of course, to avoid duplicate symbol land, but with clever
tricks and correct usage of system libraries, this is possible. To see why this
would be useful, imagine that you have some executable such as `ls`, `make` --
you  name it. Naturally, these executables reference structures and call
functions, which they would either define themselves or link
to from static or shared libraries, such as `libc`. Now, imagine that you could
provide your own definitions for the symbols an executable depends on and make
the program reference *your symbols* rather than the original ones -- basically
*injecting* your definitions. This is precisely what the
`LD_PRELOAD` trick allows us to do.

Let's see how. First, we'll write a small piece of C code as a playground for our injections. It simply reads a string from `stdin` and outputs it:

`main.c`:

```c
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

int main(int argc, const char *argv[]) {
  char buffer[1000];
  int amount_read;
  int fd;

  fd = fileno(stdin);
  if ((amount_read = read(fd, buffer, sizeof buffer)) == -1) {
    perror("error reading");
    return EXIT_FAILURE;
  }

  if (fwrite(buffer, sizeof(char), amount_read, stdout) == -1) {
    perror("error writing");
    return EXIT_FAILURE;
  }

  return EXIT_SUCCESS;
}
```

Then, we compile the file into a regular executable:

```shell
$ gcc main.c -o out
```

If you run it and give it some input, it should behave as expected:

```shell
$ ./out
>>> foo
>>> foo
```

Next, we'll put on our mad scientist hat and write a new definition for the `read` syscall that we'll then load before the definition provided by the standard C library. For this, we simply redefine `read` with the exact same signature as the original syscall, which you can find on its [man page](http://linux.die.net/man/2/read). Because we are very evil, we will not actually read the user's input, but simply return the string "I love cats" ([why?](https://i.imgur.com/OpFcp.jpg)):

`inject.c`:
```c
#include <string.h>

ssize_t read(int fd, void *data, size_t size) {
  strcpy(data, "I love cats");
  return 12;
}
```

Note that I don't care much for boundary checking here, though you obviously would for your purposes. Now, the fantastic thing about the `LD_PRELOAD` trick is that it's so little work. Most importantly, we won't have to touch a singe line of code in the original executable and not recompile it. All we have to do is compile our injection into a shared library:

```shell
$ gcc -shared -fPIC -o inject.so inject.c
```

And use the `LD_PRELOAD` trick by setting the appropriate environment variable `LD_PRELOAD` to the path to our shared library, before executing our target program as usual:

```shell
$ LD_PRELOAD=$PWD/inject.so ./out
```

Rather than reading user input, this will simply print `I love cats`. Note how we use `$PWD` when specifying the path to the library. This is important in case the executable's working directory differs from the current directory. Also note that if you were to simply `export LD_PRELOAD=$PWD/inject.so` rather than prepending the environment variable to the executable, you would overwrite the `read` syscall for *every executable* in your system, which I obviously highly recommend.

### OS X

The `LD_PRELOAD` trick also works on OS X (macOS if you're trendy), though it's called the `DYLD_INSERT_LIBRARIES` trick there ... or maybe that name is not sexy enough. Let's just call it the `LD_PRELOAD` trick on OS X. In any case, you'll want to compile your library into a `.dylib` file:

```shell
$ gcc -shared -fPIC -o inject.dylib inject.c
```

and then use the following line to inject your code:

```shell
$ DYLD_INSERT_LIBRARIES=$PWD/inject.dylib DYLD_FORCE_FLAT_NAMESPACE=1 ./out
```

which should do the trick.

## Symbol Fishing

Another requirement we may have when doing our malicious code-injections is to retrieve the original symbol --- *symbol fishing*, as I like to call it. Say you've successfully replaced the `write` syscall with your own shared-library definition, such that all calls to `write` end up resolving to your function. Often, your goal will not be to actually entirely replace the syscall, but rather to wrap it. For example, we may only want to log that the user made the call or echo some of the parameters, but ultimately call the original definition to effectively make your injection transparent to the program. Fortunately, this is also possible! For this, we can retrieve the original symbol using the `<dlfcn.h>` system library, which provides a [`dlsym`](http://pubs.opengroup.org/onlinepubs/009695399/functions/dlsym.html) function to retrieve symbols from the dynamic linker:

`inject.c`:

```c
#define _GNU_SOURCE

#include <string.h>
#include <dlfcn.h>
#include <stdio.h>

typedef ssize_t (*real_read_t)(int, void *, size_t);

ssize_t real_read(int fd, void *data, size_t size) {
  return ((real_read_t)dlsym(RTLD_NEXT, "read"))(fd, data, size);
}

ssize_t read(int fd, void *data, size_t size) {
  strcpy(data, "I love cats");
  return 12;
}
```

As you can see, we tell the `dlsym` function the name of the symbol we want to load as a plain string. It will then retrieve the structure, variable or, relevant to our use, function and return it as a `void*`, which we can safely cast to our `typedef`'d function pointer type. You'll also notice that we supply the `RTLD_NEXT` macro to the call, which is the only other value allowed for this parameter after `RTLD_DEFAULT`. `RTLD_DEFAULT` would simply load the default symbol present in the global scope, which is the same one accessible by direct invocation or reference in program code (our definition). On the other hand, `RTLD_NEXT` will apply a symbol resolution algorithm to find any definition for the requested symbol other than the default one -- i.e. the *next* one in the linker's load order. In our case, this *next* symbol will be the original definition of `read` in `libc`. Lastly, note that we need to define the `_GNU_SOURCE` macro to enable the dynamic linker functionality we require in our code, to have access to certain GNU extensions.

Once we've retrieved the original syscall with `dlsym`, we can simply call it with the arguments it would normally take. As a result, we can now invoke the original syscall from within our evil variant to, for example, print everything the user `read`s to `stdout` before returning the original data:

`inject.c`:
```
#define _GNU_SOURCE

#include <dlfcn.h>
#include <stdio.h>

typedef ssize_t (*real_read_t)(int, void *, size_t);

ssize_t real_read(int fd, void *data, size_t size) {
  return ((real_read_t)dlsym(RTLD_NEXT, "read"))(fd, data, size);
}

ssize_t read(int fd, void *data, size_t size) {
  ssize_t amount_read;

  // Perform the actual system call
  amount_read = real_read(fd, data, size);

  // Our malicious code
  fwrite(data, sizeof(char), amount_read, stdout);

  // Behave just like the regular syscall would
  return amount_read;
}
```

Finally, we'll have to recompile our shared library with the `-ldl` flag to link the `dl` library, which is necessary for our dynamic linker magic:

```shell
gcc -shared -fPIC -ldl -o inject.so inject.c
```

We can already do some exciting things with our injection. Simply run it in front of arbitrary executables in your system to see fun things happen. For example, we can spy on `gcc` compiling our library that spies on `gcc` compiling our library that spies on `gcc` compiling our library that ...

```shell
LD_PRELOAD=$PWD/inject.so gcc -shared -fPIC -ldl -o inject.so inject.c
```

## Outro

I hope this article gave you some useful pointers on the `LD_PRELOAD` trick. The code, methods and commands I gave you in this article are essentially all you need to write your own syscall definitions and inject code into other executables. Note however, that you'll have a hard time doing really evil things with this trick, as the dynamic loader will only load your library if the effective user ID equals the real user ID, i.e. if you own the executable you are attempting to inject code into. That said, there's lots of exciting things you can do to better the world. If you want to see how I used it to replace domain socket communication with shared memory channels, head over to [tssx](https://github.com/goldsborough/tssx).

Lastly, here are some additional resources you may find useful:

* https://rafalcieslak.wordpress.com/2013/04/02/dynamic-linker-tricks-using-ld_preload-to-cheat-inject-features-and-investigate-programs/
* http://stackoverflow.com/questions/426230/what-is-the-ld-preload-trick
* http://pubs.opengroup.org/onlinepubs/009695399/functions/dlsym.html
* http://tldp.org/HOWTO/Program-Library-HOWTO/dl-libraries.html
