---
layout:     post
title:      Bit Manipulation
summary:    Tips and concepts associated with bit-manipulation and a few sample problems.
date:       2015-10-11 23-52-02
categories: bits, c++, low-level, problems
---

Very often when working with programming languages that are just in any way higher level than assembly, such as when building web services, desktop applications, mobile apps -- you name it -- we may forget about the lower-level happenings in our systems: the bits and bytes and niddy-griddy details. Often, we actually *wish* to forget about those happenings and will abstract, encapsulate and wrap operations on those bits and bytes in classes and objects to make our lives easier. However, just as problematic it would be to have to deal with bit-manipulation to achieve even the simplest things and write even the simplest program, it is just as problematic to forget about how to flip bits, form masks and use the binary system to our advantage.

This post will outline a few tips and practical concepts regarding bit-manipulation and show how they can be used to solve actual problems (taken from *[Cracking the Coding Interview](http://goo.gl/yrtWHv)*).

After reading this, you should be able to upgrade to this keyboard, for "real" programmers:

<div style="text-align: center">
    <img  src="http://goo.gl/Y7djnD" alt="keyboard"/>
</div>

## Table of Contents

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->


- [Basic Concepts](#basic-concepts)
  - [Binary Operations](#binary-operations)
  - [Bit-Manipulation](#bit-manipulation)
- [Tricks](#tricks)
  - [Determining if a Value is a Power of Two](#determining-if-a-value-is-a-power-of-two)
  - [Masks](#masks)
  - [Finding the LSB](#finding-the-lsb)
- [Problems](#problems)
  - [Determining the Cardinality](#determining-the-cardinality)
  - [Bit-Merging](#bit-merging)
  - [Floating-Point Representation](#floating-point-representation)
  - [Bit-Twins](#bit-twins)
  - [Edit-Distance for Bits](#edit-distance-for-bits)
  - [Even-Odd Bit-Swapping](#even-odd-bit-swapping)
  - [Drawing a Line in a Monochrome Screen.](#drawing-a-line-in-a-monochrome-screen)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

## Basic Concepts

First, we should lay out the basics. I'm assuming you know what the binary system is, that it only uses the digits `0` and `1` and that the $n^{th}$ bit (including $0$) corresponds to a value of $2^n$.

Just some nomenclature:

* If a bit is *unset*, *low*, *LOW* or *cleared*, we mean it is 0.
* If a bit is *set*, *high* or *HIGH*, we mean it is 1.
* *Setting* a bit means making 1.
* *Clearing* or *unsetting* a bit means making it 0.
* The left-most-bit has the highest value and is thus termed the *most-significant-bit* (MSB).
* The right-most-bit has the lowest value and is thus called the *least-sinificant-bit* (LSB).
* The *cardinality* of a value refers to the number of bits it has *set* (i.e. the number of 1s.

### Binary Operations

Now follow basic binary concepts. You may very well be familiar with these operations, so feel free to skip them.

#### Addition

To add two binary values in your head, you can either first convert them to decimal and then do the addition there (and possibly re-convert the result to binary), or just do addition like you learnt it in primary school.

*Example:* Perform the operation $1101\_2 + 1010\_2$

1. Convert $1101\_{2}$ to $13\_{10}$ and $1010\_2$ to $10\_{10}$ and then easily do $13 + 10 = 23$

2. Write the two numbers beneath each other and follow the rules:
    * $0 + 0$ give $0$
    * $0 + 1$ give $1$
    * $1 + 1$ give $0$ with a carry of $1$ (add that at the next digit)

```
 1101
     +
 1010
_____
10111
```

#### Subtraction

Analog for subtraction (with a little extra complexity for subtraction):

*Example:* Perform the operation $1101\_2 - 1010\_2$

1. Once more convert $1101\_2$ to $13\_{10}$ and $1010\_2$ to $10\_{10}$ and then do basic math $13 - 10 = 3$

2. Write the two numbers beneath each other and follow the rules:
    * `0 - 0` give `0`
    * `1 - 0` give `1`
    * `1 - 1` give `0`
    * `10 - 1` give `01` (borrow) and generally a `1` followed by $n$ `0`s gives a `0` followed by $n$ `1s`

#### Multiplication

Multiplication is a bit more complicated, but basically involves shifting bits around:

*Example:* Perform the operation $1101\_2 \cdot 1010\_2$

1. $1101\_2 \cdot 1010\_2 = 13\_{10} \cdot 10\_{10} = 130$

2. For multiplication you have to work on a bit-by-bit basis and "multiply" each bit `A` in the one value by each bit `B` in the other value by shifting `B` over by the position of `B`. You then have to add the result of each shift operation. For example, with `x = 4 = 0b0100` and `y = 2 = 0b0010`, to do $x \cdot y$, you have to shift `x` over by the position of every bit in `y`. For `x`, here, there is only the $2^{nd}$ bit (`0`-indexed) and for `y` only the $1^{st}$. For the result, you would now have to shift `x` to the left by the index of the bit in `y`, i.e. by one position. The result is then `0b1000 = 8`. If there were more bits in `x`, you would repeat this for all other bits and add the results of each shift for the final result.

```
    1101
         x
    1010
________
10000010
```

#### OR

The OR operation is the first binary-only operation (can't do it in decimal). In most programming languages, it is performed with the `|` (bar) operator. To OR two binary values, you follow the rules that, for every bit:

* `0 | 0 = 0`
* `0 | 1 = 1`
* `1 | 1 = 1`

The basic idea is, the bit will be set if one *or* the other is, but you most likely know that from boolean expressions in programming.

#### AND

For boolean AND -- usually represented by the `&` (ampersand) character --, a bit is only set if both the bit in the first value *and* in the second value are set, such that:

* `0 & 0 = 0`
* `0 & 1 = 0`
* `1 & 1 = 1`

#### XOR

XOR, short for "exclusive-OR", sets a bit only if the bits in the two values differ, i.e. if `bit1 != bit2`:

* `0 ^ 0 = 0`
* `0 ^ 1 = 1`
* `1 ^ 1 = 0`

#### Complement

Complementing, also called *twiddling*, *negating* or simply *flipping*, changes all $1$s to $0$s and vice-versa. Note that this is a *unary* operation, not a binary operation, meaning it is performed on only one value and not on/between two values (as is AND, OR and XOR). Its character is the tilde: `~`.

* `~10101101 = 01010010`
* `~1111 = 0000`
* `~0 = 1`

#### Shifting

Shifting, to the left with `<<` and to the right with `>>`, shifts a binary value to the left or right by a certain number of bits. Note that in Java, there exist also the `<<<` and `>>>` operators, which also shift the sign-bit (while `>>` would only shift the bits to the right of the sign-bit).

* `0001 << 3 = 1000`
* `1010 >> 2 = 0010`

### Bit-Manipulation

While the above paragraphs show how to use the operators available for bit operations, they do not yet answer questions such as how to set, clear or update bits. These manipulation-techniques are described below.

#### Setting Bits

For setting a bit, the OR operation is ideal, as OR-ing a bit with `1` will always result in that bit being `1`, whether it was `1` before or not. You may have first thought of XOR-ing an unset bit with `1`, but that would clear the bit if it was already set. That's why the common method is to do something along the lines of the following:

To set the $n^{th}$ bit (starting at 0) of a value `x`: `x |= (1 << n)`

* `0000 | (1 << 0) = 0000 | 0001 = 0001`
* `1000 | (1 << 1) = 1000 | 0001 = 1010`
* `0100 | (1 << 2) = 0100 | 0100 = 0100` (no change)

For example, when working with microcontrollers, I always have a macro like this (note that this is for working with microcontrollers with a few KB of RAM where macros are often better than function calls, in any higher-level language you should always prefer functions):

`#define SET_BIT(byte, bit) ((byte) |= (1UL << (bit)))`

#### Clearing Bits

To clear a bit, we use the AND (`&`) and NOT (`~`) operations. To clear/unset the $n^{th}$ bit of a value, the basic idea is to create a bit-mask with all bits set except for that $n^{th}$ bit, and then to AND the value with this mask. All bits that were previously set will be left alone, because `1 & 1 = 1` and all bits that were unset will also remain unset, because `0 & 1 = 0`. 

To clear the $n^{th}$ bit of a value `x`: `x &= ~(1 << n)`.

* `0111 & ~(1 << 0) = 0111 & 1110 = 0110`
* `0100 & ~(1 << 2) = 0100 & 1011 = 0000`
* `0111 & ~(1 << 3) = 0111 & 0111 = 0111` (no change)

Macro:

`#define CLEAR_BIT(byte,bit) ((byte) &= ~(1UL << (bit)))`

#### Toggling Bits

We use XOR with `1` to toggle a bit. This operation will always flip a `0` to a `1` and a `1` to a `0`.

To toggle the $n^{th}$ bit of a value `x`: `x ^= (1 << n)`

* `0010 ^ (1 << 1) = 0010 ^ 0010 = 0000`
* `0110 ^ (1 << 0) = 0110 ^ 0001 = 1111`

Macro:

`#define TOGGLE_BIT(byte,bit) ((byte) ^= (1UL << (bit)))`

#### Updating Bits

Sometimes we may want to update a bit to specific value, stored in a variable. For this, we first have to clear the bit, and then OR it with the value.

To update the $n^{th}$ bit of a value `x`:

1. `x &= ~(1 << n)`
2. `x |= (1 << value)`

#### Checking Bits

Of course, we'd also like to know if bits are set or not. For this, we AND the bit with a 1. If the bit was set, the result will be a 1 and else a 0. This also evaluates nicely to boolean true and false, thus you can use it in an if clause.

To check the $n^{th}$ bit of a value `x`: `x & (1 << n)`

For example, you can check if a value is odd by AND-ing the first (i.e. $0^{th}$) bit:

{% gist a2b8114bb36eecf814e8 %}

I actually much prefer this way of checking for evenness, but most people are more familiar with the modulo method (even if `x % 2 == 0`) so I tend to stick with the modulo method for compliance.

Macro below. Note how here, after performing the AND operation, we shift the the result back to the right so that the set or cleared bit is at index 0. This is if we want to check the bit in a higher-bitwidth value and then store the result in a lower-bitwidth value, e.g. check the $31^{st}$ bit of a 32-bit unsigned integer and store the result in an 8-bit unsigned char. The bits more-significant than the $7^{th}$ bit get lost during casting.

`#define IS_SET(byte,bit) (((byte) & (1UL << (bit))) >> (bit))`

## Tricks

First, two simple tricks that can be useful for bit-manipulation.

### Determining if a Value is a Power of Two

The great thing about powers of two is that they occupy only a *single* bit in their binary representation. Thus, to determine if a value is a power of two, just check if they only have a single bit set. Easy! Right? In fact not so much. You could do something overkill like so:

```Python
import math

log = math.log2(value)

if int(log) == log:
    ...
```

But there's really a nice trick to doing this: A value `x` is a power of 2 if you can `AND` `x` with `x - 1` and have the result be `0`.

Example: `x = 16`

```
x:     00010000
                AND
x - 1: 00001111
_______________
       00000000
```

Counterexample: `x = 6`

```
x:     00000110
                AND
x - 1: 00000101
_______________
       00000100
```

### Masks

#### Of Exactly $N$ Bits

To create a mask of `N` bits, shift 1 over by `N` positions to the left and subtract 1:

`N = 4` (you want a mask of 4 bits): `(1 << 4) - 1 = (10000) - 1 = 01111`

#### Of All Odd Bits

To get a mask for all odd bits, use `0xA`, with one `A` every four bits (2 for a byte, 16 for a 64-bit `std::size_t` in C++).

```Python
>>> bin(0xAA)
>>> '0b10101010' 
```

With the explanation that `0xA` in hex is `10` in decimal which is `0b1010` in binary (and the $1^{st}$ and $3^{rd}$ bits are set).


#### Of All Even Bits

The analog for all even bits is `0x5`, as `0x5` is `0b0101` in binary, where all even bits are set.


```Python
>>> bin(0x55)
'0b1010101'
```

### Finding the LSB

Your first inclination to find the least-significant-bit (LSB) may be to search all bits in order of increasing significance util a bit is set:

{% gist 869aa6080668d6c6e9e1 %}

While this works, its complexity is `O(N)` where `N` is the bitwidth of the data-type `T` used to represent the value. Using some super-awesome tricks we can get this down to constant-time:

Example: `A: 011010`

First, subtract `1` from `A` to complement the bits before the LSB.

`B: 011010 - 1 = 011001`

Then, OR `A` with `B`, such that all bits before and including the LSB are set in `A`:

```Python
A: 011010
           OR
B: 011001
_________
C: 011011
```

The consequence is that when you now XOR `B` with `C`, the only position where bits differ is at the LSB (because you also set the bits before the LSB and the bits after it are unaffected).

```
C: 011011
          XOR
B: 011001
_________
D: 000010
```

If you now take base-2 logarithm of this value you get the LSB position.

{% gist 80f422ff58e7772a026e %}

I know, it's a bit magic.

## Problems

Here follow some problems regarding bit-manipulation, many taken from *[Cracking the Coding Interview](http://goo.gl/yrtWHv)*), to which all credit goes for them.

### Determining the Cardinality

*Determine the cardinality of a value (how many bits are set).*

We'll have to count, but optimize a bit by testing if the value is a power of 2 or one value before a power of 2.

{% gist a9b67def8fd0c77f3976 %}

### Bit-Merging

*You are given two 32-bit number, `N` and `M`, and two bit positions `i` and `j` with `i` being less significant than `j`. Insert `M` into `N` at those positions.*

Solution: Create a proper mask to unset the bits between `i` and `j` in `N`, then shift `M` over by `i` bits and `or` them.

1. Create the mask.
    + For signed integers: `-~0 << j | ((1 << i) - 1)` (first set the bits to the left of the interval, then add, i.e. `or`, the bits to the right of it.)
    + For unsigned types also: `~(((1 << (j - i)) - 1) << i)` (create the mask of correct length, shift them into place, then twiddle).
2. Binary `AND` `N` by the mask, to clear the relevant bits between i and j.
3. Simply "insert" `M` by `OR`ing `N` by `M`.

{% gist 504808a000f2a196874a %}

### Floating-Point Representation

*Given a real number between 0 and 1, print its binary representation if it can be represented with at most 32 characters, else print "Error".*

Note: Binary numbers are generally structured such that each bit signifies $0$ or $1 \cdot 2^N$. This is true for positive values, i.e. `101` means, from right to left, $1 \cdot 2^0 + 0 \cdot 2^1 + 1 \cdot 2^2 = 5$. But it is also true for negative values, where each digit to the right of the `0/1` bit stands for $1 \text{ or } 0 \cdot 2^{-N}$ (note the minus), such that `0.101` means $1 \cdot 2^{-1} = 1 \cdot \frac{1}{2} \dots$

Solution: Start with a "significance" of $0.5$ and see if we can subtract that significance from the floating-point value. If so, we add a 1 to our representation and subtract the significance from the value. If not, we add a 0 to the representation. Before each next iteration, we divide the significance by 2 to get $0.5, 0.25, 0.125, ...$

{% gist 3f50d1625b61e9b9d84e %}

### Bit-Twins

*Given an integer with $N$ bits, find the next greater and smaller values with the same number of bits set as that integer.*

Solution 1: Brute force. Increment the value and compute its cardinality each time, until the cardinality matches that of the original value. Same for decrementing. This algorithm's complexity would be $O(N \cdot B)$ where $N$ is the number of values we must check and $B$ the bitwidth of the data-type.

{% gist 74955a45ade6489facd5 %}

Solution 2: Go full-hardcore. See comments.

{% gist ff48d97864c7ddfc51e0 %}

### Edit-Distance for Bits

*Write a function to determine the number of bits you would need to flip to convert integer $A$ to integer $B$*.

Definitely, one would want to `XOR` the two integers to determine which bits differ. Then, it depends on how optimize the counting of bits.

Solution 1: Count between the LSB and MSB of the `XOR`ed value:

{% gist 70a1d0a85afbfac4393c %}

Solution 2: As above, but move to then next LSB each time (can skip some bits with a constant-time operation):

{% gist dfec8c309a85c9190dfc %}

### Even-Odd Bit-Swapping

*Write a program to swap odd and even bits in an integer with as few instructions as possible*

Solution 1: Iterative and inefficient.

{% gist f363b32517c78e5db048 %}

Solution 2: Mask off the odd bits and do shifting.

An appropriate mask for all odd bits is `0xAA` (two `A`s for every 8 bits / one for every 4). We first unset the odd bits, then shift the value to the left by one position to put the even bits into the odd positions. Then, we grab the odd bits, right shift (or left shift) those, and or the two sides.

{% gist e47dd2c01e349b274e10 %}

### Drawing a Line in a Monochrome Screen.

*A monochrome screen is a single array of bytes, allowing eight consecutive pixels to be stored in one byte and `w` bytes in one row. Given a vertical row index `y` and two `x`-indices (bits in those bytes) `x_1` and `x_2`, write a function to draw a line between those bits, on that row.*

Be careful about edge cases.

{% gist 542b40696a4271e551e7 %}

## Farewell

And that's it for this article on bit-manipulation. Hope you learnt something!