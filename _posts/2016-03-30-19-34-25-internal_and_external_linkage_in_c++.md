---
layout:		post
title:		Internal and External Linkage in C++
summary:	All you need to know about linkage in C++
date:		2016-03-30 19-34-25
categories:	c c++ linker
---

Ever come across the terms *internal and external linkage*? Ever wanted to know
what the `extern` keyword is for and what declaring something `static` does in
the global scope? Then this post is for you.

## TL;DR

A *translation unit* refers to an implementation file and all header files it
includes. If an object or function inside such a translation unit has *internal
linkage*, then that specific symbol is only visible to the linker within that
translation unit. If an object or function has *external linkage*, the linker
can also see it when processing other translation units. The `static` keyword,
when used in the global namespace, forces a symbol to have internal linkage. The
`extern` keyword results in a symbol having external linkage.

The compiler defaults the linkage of symbols such that:

* *Non-const* global variables have *external* linkage by default
* *Const* global variables have *internal* linkage by default
* Functions have *external* linkage by default

## Table of Contents

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->

- [Table of Contents](#table-of-contents)
- [Basics](#basics)
  - [Declaration vs. Definition](#declaration-vs-definition)
  - [Translation Units](#translation-units)
- [Linkage](#linkage)
  - [External Linkage](#external-linkage)
  - [Internal Linkage](#internal-linkage)
- [References](#references)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

## Basics

Lets first cover two rudimentary concepts that we'll need to properly discuss
linkage:

1. The difference between a declaration and a definition
2. Translation Units

Also, just a quick word on naming: we'll use the term *symbol* to refer to any
kind of "code entity" that a linker works with, i.e. *variables* and *functions*
(and also classes/structs, but we won't talk much about those).

### Declaration vs. Definition

Lets quickly discuss the difference between *declaring* a symbol and *defining*
a symbol: A *declaration* tells the compiler about the existence of a certain
symbol and makes it possible to refer to that symbol everywhere where the
explicit memory address of that symbol is not required. A *definition* tells the
compiler what the body of a function contains or how much memory it must
allocate for a variable.

#### Functions

The difference between the declaration and definition of a function is fairly
obvious:

```C++
int f();               // declaration
int f() { return 42; } // definition
```

#### Variables

For variables, it is a bit different. Declaration and definition are usually
not explicitly separate. *Most importantly*, this:

```c++
int x;
```

Does not just declare `x`, but also define it. In this case, by calling the
default constructor of `int` (which does nothing). You can, however, explicitly
separate the declaration of a variable from its definition by using the `extern`
keyword:

```c++
extern int x; // declaration
int x = 42;   // definition
```

However, when `extern` is prepended to the declaration and an initialization is
provided as well, then the expression turns into a definition and the `extern`
keyword essentially becomes useless:

```c++
extern int x = 5; // is the same thing as
int x = 5;
```

#### Usage Frequency

One very important difference between declarations and definitions is that a
symbol may be *declared many times, but defined only once*. For example, you can
forward declare a function or class however often you want, but you may only
ever have one definition for it. This is called the
[one definition rule](https://en.wikipedia.org/wiki/One_Definition_Rule). Therefore,
this is valid C++:

```c++
int f();
int f();
int f();
int f();
int f();
int f();
int f() { return 5; }
```

While this isn't:

```c++
int f() { return 6; }
int f() { return 9; }
```

### Translation Units

Programmers usually deal with header files and implementation files. Compilers
don't -- they deal with *translation units* (TUs), sometimes referred to as
*compilation units*. The definition of such a translation unit is very simple:
Any file, fed to the compiler, *after it has been pre-processed*. In detail,
this means that it is the file resulting from the pre-processor expanding
macros, conditionally including source code depending on `#ifdef` and `#ifndef`
statements and copy-pasting any `#include`ed files.

Given these files:

`header.hpp`:

```c++
#ifndef HEADER_HPP
#define HEADER_HPP

#define VALUE 5

#ifndef VALUE
struct Foo { private: int ryan; };
#endif

int strlen(const char* string);

#endif /* HEADER_HPP */
```

`program.cpp`:

```c++
#include "header.hpp"

int strlen(const char* string)
{
	int length = 0;

	while(string[length]) ++length;

	return length + VALUE;
}
```

The pre-processor will produce the following translation unit, which is then fed
to the compiler:

```c++
int strlen(const char* string);

int strlen(const char* string)
{
	int length = 0;

	while(string[length]) ++length;

	return length + 5;
}
```

## Linkage

Now that we've covered the basics, we can deal with linkage. In general, linkage
will refer to the visibility of symbols to the linker when processing
files. Linkage can be either *internal* or *external*.

### External Linkage

When a symbol (variable or function) has external linkage, that means that that
symbol is visible to the linker from other files, i.e. it is "globally" visible
and can be shared between translation units. In practice, this means that you
must define such a symbol in a place where it will end up in one and only one
translation unit, typically an implementation file (`.c`/`.cpp`), such that it
has only one visible definition. If you were to define such a symbol on the
spot, along with declaring it, or to place its definition in the same file you
declare it, you run the risk of making your linker very angry. As soon as you
include that file in more than one implementation file, such that its definition
ends up in more than one translation unit, your linker will start crying.

In C and C++, the `extern` keyword (explicitly) declares a symbol to have
external linkage:

```c++
extern int x;
extern void f(const std::string& argument);
```

Both of these symbols have external linkage. Above it was mentioned that `const`
global variables have *internal* linkage by default, and non-`const` global
variables have *external* linkage by default. That means that `int x;` is the
same as `extern int x;`, right? Not quite. `int x;` is actually the same as
`extern int x();`, as `int x;` not only declares, but also defines
`x`. Therefore, not prepending `extern` to `int x;` in the global scope is just
as bad as also defining a variable when declaring it as `extern`:

```c++
int x;          // is the same as
extern int x(); // which will both likely cause linker errors.

extern int x;   // while this only declares the integer, which is ok.
```

#### Usage

A common use case for declaring variables explicitly `extern` are global
variables. For example, say you are working on a self-baking cake. There may be
certain global system variables connected with self-baking cakes that you need
to access in various places throughout your program. Let's say the clock-rate of
the edible chip inside your cake. Such a value would naturally be required in
many, many places to make all the chocolate electronics work synchronously. The
C (evil) way of declaring such a global variable would be a macro:

```C
#define CLK 1000000
```

A C++ programmer, naturally despising macros, would rather use real code. So you
could do this:

```c++
// global.hpp

namespace Global
{
	extern unsigned int clock_rate;
}

// global.cpp
namespace Global
{
	unsigned int clock_rate = 1000000;
}
```

(As a modern C++ programmer, you might also want to take advantage of (separator
literals)[http://www.informit.com/articles/article.aspx?p=2209021]: `unsigned
int clock_rate = 1'000'000;`)

### Internal Linkage

When a symbol has *internal linkage*, it will only be visible within the current
translation unit. Do not confuse the term *visible* here with access rights like
`private`. *Visibility* here means that the linker will only be able to use this
symbol when processing the translation unit in which the symbol was declared,
and not later (as with symbols with external linkage). In practice, this means
that when you declare a symbol to have internal linkage in a header file, each
translation unit you include this file in will get *its own unique copy of that
symbol*. I.e. it will be as if you would redefine each such symbol in every
translation unit. For objects, this means that the compiler will literally
allocate an entirely new, unique copy for each translation unit, which can
obviously incur high memory costs.

To declare a symbol with internal linkage, C and C++ provide the `static`
keyword. Its usage here is entirely separate from its usage in classes or
functions (or, generally, any block).

#### Example

Here an example:

`header.hpp`:

```c++
static int variable = 42;
```

`file1.hpp`:

```c++
void function1();
```

`file2.hpp`:

```c++
void function2();
```

`file1.cpp`:

```c++
#include "header.hpp"

void function1() { variable = 10; }
```

`file2.cpp`:

```c++
#include "header.hpp"

void function2() { variable = 123; }
```

`main.cpp`:

```c++
#include "header.hpp"
#include "file1.hpp"
#include "file2.hpp"

#include <iostream>

auto main() -> int
{
	function1();
	function2();

	std::cout << variable << std::endl;
}
```

Because `variable` has internal linkage, each translation unit that includes
`header.hpp` gets its own unique copy of `variable`. Here, there are three
translation units:

1. file1.cpp
2. file2.cpp
3. main.cpp

When `function1` is called, `file1.cpp`'s copy of `variable` is set to 10. When
`function2` is called, `file2.cpp`'s copy of `variable` is set to 123. However,
the value printed out in `main.cpp` is `variable`, unchanged: 42.

#### Anonymous Namespaces

In C++, there exists another way to declare one or more symbols to have internal
linkage: anonymous namespaces. Such a namespace ensures that the symbols
declared inside it are visible only within the current translation unit. It is,
in essence, just a way to declare many symbols as `static`. In fact, for a
while, the `static` keyword for the use of declaring a symbol to have internal
linkage was deprecated in favor of anonymous namespaces. However, it was
recently *undeprecated*, because it is useful to declare a single variable or
function to have internal linkage. There are also a few minor differences which
I won't go into here.

In any case, this:

```c++
namespace { int variable = 0; }
```

does (almost) the same thing as this:

```c++
static int variable = 0;
```

#### Usage

So when and why would one make use of internal linkage? For objects, it is
probably most often a very bad idea to make use of it, because the memory cost
can be very high for large objects given that each translation unit gets its own
copy. However, one interesting use case could be to hide translation-unit-local
helper functions from the global scope. Imagine you have a helper function `foo`
in your `file1.hpp` which you use in `file1.cpp`, but then you also have a
helper function `foo` in your `file2.hpp` which you use in `file2.cpp`. The
first `foo` does something completely different than the second `foo`, but you
cannot think of a better name for them. So, you can declare them both
`static`. Unless you include both `file1.hpp` and `file2.hpp` in some same
translation unit, this will hide the respective `foo`s from each other. If you
don't declare them `static`, they will implicitly have external linkage and the
first `foo`'s definition will collide with the second `foo`s definition and
cause a linker error due to a violation of the one-definition-rule.

## References

* http://stackoverflow.com/questions/154469/unnamed-anonymous-namespaces-vs-static-functions
* http://stackoverflow.com/questions/4726570/deprecation-of-the-static-keyword-no-more
* http://www.geeksforgeeks.org/understanding-extern-keyword-in-c/
