---
layout:		post
title:		Emitting Diagnostics in Clang
summary:	I explain thow to plug into the available infrastructure for diagnostics and fixit hints for custom clang tools.
date:		2017-02-24 00-00-06
categories:	c++ clang llvm tools
---

One of the major strong points of the [clang compiler
project](http://clang.llvm.org) has always been its commitment to produce clear,
correct, precise and especially *human-readable* diagnostics. Given that clang
is the frontend for a language that is infamous for error messages that make
even the bravest and most experienced of programmers lose their last ounce of
hope (and switch to Rust), emitting understandable error messages is a big deal.
One really comes to appreciate clang's clarity when we compare it to other
compilers. Take this simple snippet of code as an example:

```cpp
int x
int y;
```

If we compare what gcc (6.3) says about this:

```
f.cpp:2:2: error: expected initializer before 'int'
  int y;
  ^~~
```

as opposed clang (4.0):

```
f.cpp:1:6: error: expected ';' after top level declarator
int x
     ^
     ;
1 error generated.
```

we can see that even when it comes to the little things, clang pays attention
and points out the *actual* problem, whereas gcc just complains about the
consequence.

There are numerous other ways in which the clang development community's hard
work to get diagnostics right (from the start) shine out, from dealing with
macros and typedefs all the way to printing pretty trees for the enigmatic
templates C++ is famous for. You can read more about this
[here](https://clang.llvm.org/diagnostics.html).

Since clang and LLVM as a whole are not designed as monolithic blobs of code,
but rather as a set of (reasonably) standalone libraries, the best thing about
diagnostics in clang is that we can make use of them ourselves when building our
own clang tools. Documentation and practical examples of using clang's
diagnostics APIs are sparse on the web, so the next few paragraphs will discuss
some basic concepts as well as the internal source code and implementation.
We'll begin by looking at emitting plain diagnostics and later investigate
*FixIt hints* to provide useful suggestions to the users of our tools.

Note that this post is best read with some prior experience with clang tooling.
You can still read it if you're just starting out, I just won't go into the
details of every line that's not so relevant to diagnostics.

# Diagnostics

One of the most exciting aspects of my clang tooling journey so far has been
diving deep into the clang (and LLVM) source tree and learning about the project
by looking at how stuff is implemented. Fortunately, LLVM is probably one of the
cleanest and best maintained large-scale codebases in the wild, so popping up a
source file is usually fun rather than painful. As such we'll learn about
diagnostics in clang by discussing the classes that make up the API. We begin
with the `DiagnosticsEngine` class, which is the `ASTContext` of the diagnostics
world. We then take a closer look at the `DiagnosticBuilder` class, which is
always used alongside the engine to build diagnostics. Finally we'll briefly
delve into the `DiagnosticsConsumer` side of things and see how clang's
diagnostics end up where they do.

## `DiagnosticsEngine`

The `DiagnosticsEngine` class is one of the main actors in clang's
diagnostic-reporting architecture and your first stop when wanting to emit a
diagnostic. Its primary purpose is to provide a way to report a diagnostic via
its `Report` method and then to allow configuration of various "meta" aspects of
diagnostic reporting. For example, you can configure what diagnostics will be
suppressed, whether warnings should show as errors, what the limit on showing
nested template declarations is before they are elided, whether colors should be
shown or if errors should be printed as a tree. You can find the declaration
(and a lot of the definition) of the `DiagnosticsEngine` class in
`include/clang/Basic/Diagnostic.h` (relative to the clang root), around line 150. In here, for example, we see that diagnostics can be emitted at a certain
level:

```cpp
enum Level {
  Ignored = DiagnosticIDs::Ignored,
  Note = DiagnosticIDs::Note,
  Remark = DiagnosticIDs::Remark,
  Warning = DiagnosticIDs::Warning,
  Error = DiagnosticIDs::Error,
  Fatal = DiagnosticIDs::Fatal
};
```

Before being able to report a diagnostic yourself, you must request a custom
*ID* for the warning or error message you want to emit, as every diagnostic in
clang has a unique ID. This could look like so:

```cpp
// Typical clang tooling context
void run(clang::ASTContext& Context) {
  // Types shown for clarity
  clang::DiagnosticsEngine &DE = Context.getDiagnostics();
  const unsigned ID = DE.getCustomDiagID(clang::DiagnosticsEngine::Warning,
                                         "I findz a badness");
  // ...

}
```

The idea of the unique identifier is that you can reuse diagnostics that you
define once (maybe using a complex format) in the various contexts that you may
find them. This is also how the clang compiler organizes its warnings. If we
take a look at `include/clang/Basic/DiagnosticASTKinds.td`, we can see the
following error definition for accessing `volatile` expressions in `constexpr`
contexts, which is not allowed:

```cpp
def note_constexpr_access_volatile_obj : Note<
  "%select{read of|assignment to|increment of|decrement of}0 volatile "
  "%select{temporary|object %2|member %2}1 is not allowed in "
  "a constant expression">;
```

which can then be referenced via `diag::note_constexpr_access_volatile_obj` in
clang code (using its internal code generation mechanisms, which turns the `.td`
file into a `.inc` header).

### Diagnostic Formatting

As you can see from the internal clang warning about `volatile` accesses in
`constexpr` expressions, clang has a relatively powerful formatting language for
its diagnostics that you can use for templatization. The simplest way we can use
it is by passing the names of variables or other source constructs to the
message in a `printf`-like fashion. Say, for example, we were writing a tool to
ensure that all pointer variables in our code base are prefixed with `p_`. If we
find a rebellious variable without such a prefix, we could emit a nice warning
like so:

```cpp
const unsigned ID = DE.getCustomDiagID(
  clang::DiagnosticsEngine::Warning,
  "Pointer variable '%0' should have a 'p_' prefix");
```

Sneak-peaking at the `DiagnosticBuilder` (discussed below), we could later
populate this message in the following way:

```cpp
DiagnosticsEngine.Report(InsertionLoc, ID).AddString(NamedDecl.getName());
```

Besides this simple example, clang's diagnostic formatting language has quite a
few more features. You can find a full description of them
[here](https://clang.llvm.org/docs/InternalsManual.html#the-format-string), but
to name a few:

* To handle the problem of plural names, we can make use of the `%s<n>` construct. For example, when we write `Found %1 foo%s1`, this will turn into either `Found 1 foo` or `Found 42 foos`, (i.e. the plural "s" is appended automatically), removing the need to write (a) thing(s) like this.
* By writing `%select{a|b|...}<n>` we can later pass an index into this list, allowing us to reuse the same error message for different words or phrases.
* If given a `NamedDecl*`, writing `%q<n>` will print he fully qualified name (e.g. `std::string`) instead of just the unqualified name (`string`).

The `DiagnosticsEngine` can also be used to query information about a
diagnostics. For example, given that we have created a custom diagnostic ID, we
can use the following method to get information about the level of a diagnostic:

```cpp
clang::DiagnosticsEngine::Level level = DE.getDiagosticLevel(ID, SourceLocation());
```

and more ...

```cpp
DE.setConstexprBacktraceLimit();
DE.setErrorLimit(10);
DE.getPrintTemplateTree();
DE.setElideType(true);
```

## `DiagnosticBuilder`

The second piece of clang's diagnostics puzzle, after the `DiagnosticsEngine`
class, is the
[`DiagnosticBuilder`](http://clang.llvm.org/doxygen/classclang_1_1DiagnosticBuilder.html).
This is the type of the object returned by `DiagnosticsEngine::Report`. It is a
very lightweight class designed to be used immediately (i.e. not stored) to
build a diagnostic, optionally taking appropriate formatting arguments, and then
causes the diagnostic to be emitted in its destructor (usually at the end of the
scope or expression). To be more precise, once you have created a custom
diagnostic ID from an error level and message, formatted with placeholders like
`%0` and `%1`, you will use the `DiagnosticBuilder` to pass the actual values of
those arguments. For example:

```cpp
const auto ID = DE.getCustomDiagID(clang::DiagnosticsEngine::Warning,
                                   "variable %0 is bad, it appears %1 time%s1");

clang::DiagnosticBuilder DB = DE.Report(VarDecl->getLocStart(), ID);
DB.AddString(VarDecl->getName())
DB.AddTaggedVal(6, clang::DiagnosticsEngine::ArgumentKind::ak_uint);
```

Given a snippet `int x;` and given that we are matching on integers, this would
produce the following diagnostic when the `DB` variable goes out of scope:

```cpp
file.cpp:1:5: warning: variable x is bad, it appears 6 times
int x;
    ^
```

As you can see, the `DiagnosticBuilder` has quite a few ways of passing values
to substitute for the formatting placeholders. These add values in order, i.e.
the first argument you pass will set the value for `%0`, the second for `%1` and
so on. The first important method is `AddString`, which sets a string argument.
The second function is `AddTaggedVal`, which takes an integer and formats it
according to the
[`clang::DiagnosticsEngine::ArgumentKind`](http://clang.llvm.org/doxygen/classclang_1_1DiagnosticsEngine.html#aa786a2c5b973455b81ecec595f7a9c7f)
enum member, which is the second argument. Above, we specified that it was an
unsigned integer (`ak_unit`). The type `AddTaggedVal` takes is actually an
`intptr_t`, such that the integer you pass can either be a number, or a pointer
(in the usual pragmatic fashion in which clang and LLVM interpret integers),
such as to a `NamedDecl*` for the `%q<n>` formatter. For example, when matching
against a type declaration inside a namespace, like `namespace NS { class X { }; }`,
we can write something like this:

```cpp
void diagnose(clang::DiagnosticsEngine& DE, clang::CXXRecordDecl* RecordDecl) {
  const auto ID = DE.getCustomDiagID(clang::DiagnosticsEngine::Error,
                                     "detected evil type %q0");
  const auto Pointer = reinterpret_cast<intptr_t>(RecordDecl);
  const auto Kind = clang::DiagnosticsEngine::ArgumentKind::ak_nameddecl;

  DE.Report(RecordDecl->getLocation(), ID);
    .AddTaggedVal(Pointer, Kind);

  // Diagnostic emitted here
}
```

which will result in:

```
file.cpp:1:21: error: detected evil type 'A::X'
namespace A { class X { }; }
                    ^
```

![doge clang](/images/clang-diagnostics/doge-diagnostics.jpg)

### Source Ranges

Another cool thing you can do with diagnostics is highlight particular source
ranges, like clang when it complains about certain invalid expressions. For
example, when we try to add a function to an integer, clang will put markers
underneath the entire expression:

```c
// file.c
void f();
int x = 5 + f;
```

```shell
$ clang file.c
file.c:3:13: error: invalid operands to binary expression ('const char *' and 'void (*)()')
int x = "5" + f;
        ~~~ ^ ~
1 error generated.
```

We can do the same, pretty easily. In fact, we could replicate this exact error
message, just that we can't match on an invalid AST, so we'll have to take an
example that actually compiles. Given this code:

```cpp
int x = 3 + .14;
```

we can use the following `clang::ast_matchers` matcher to find all plus
operations adding an integer to a float:

```cpp
binaryOperator(
  hasOperatorName("+"),
  hasLHS(implicitCastExpr(hasSourceExpression(integerLiteral()))),
  hasRHS(floatLiteral()))
```

and then emit a diagnostic that warns about the range of this expression. For
this, we can simply pass a `clang::CharSourceRange` to the `DiagnosticBuilder`'s
`AddSourceRange` method. It's as simple as that:

```cpp
void diagnose(clang::BinaryOperator* Op, clang::ASTContext& Context) {
  auto& DE = Context.getDiagnostics();
  const auto ID = DE.getCustomDiagID(
      clang::DiagnosticsEngine::Remark,
      "operands to binary expression ('%0' and '%1') are just fine");

  auto DB = DE.Report(Op->getOperatorLoc(), ID);
  DB.AddString(Op->getLHS()->IgnoreImpCasts()->getType().getAsString());
  DB.AddString(Op->getRHS()->getType().getAsString());

  const auto Range =
      clang::CharSourceRange::getCharRange(Op->getSourceRange());
  DB.AddSourceRange(Range);
}
```

which gives us:

```cpp
file.cpp:1:11: remark: operands to binary expression ('int' and 'double') are just fine
int x = 3 + .14;
        ~~^~~~~
```

Sweet.

## `DiagnosticsConsumer`

Another member of clang's diagnostics family is the `DiagnosticsConsumer` class.
As you can imagine, clang's diagnostics are distributed via the typical
publisher-subscriber/observer pattern, so subclasses of this class are
responsible for actually printing error messages to the console, storing them in
a log file or processing them in another way. In a typical clang tool, you'll
most likely not have to interact with this aspect of the infrastructure, but
I'll nevertheless talk you through it briefly.

A `DiagnosticConsumer` subclass has the primary responsibility of overriding the
`HandleDiagnostic` method, which takes a `Diagnostic` instance and a
`DiagnosticEngine::Level` value (which is just the `Diagnostic`'s level, for
convenience). A `Diagnostic` is a container for all information relevant to a
diagnostic. Its implementation consists just of an `llvm::StringRef` to the
unformatted message and then a pointer back to the engine, so that it can get
more information when necessary. Next to `HandleDiagnostic`, we can also
override `BeginSourceFile` and `EndSourceFile`, which lets us do pre- and
post-processing, just like we can in a `FrontEndAction` or an `ASTConsumer`.

To get an idea of what subclassing `DiagnosticConsumer` looks like, we can just
look at clang's own `IgnoringDiagConsumer` inside `Basic/Diagnostic.h`:

```cpp
/// \brief A diagnostic client that ignores all diagnostics.
class IgnoringDiagConsumer : public DiagnosticConsumer {
  virtual void anchor();

  void HandleDiagnostic(DiagnosticsEngine::Level DiagLevel,
                        const Diagnostic &Info) override {
    // Just ignore it.
  }
};
```

Besides the `anchor()` function, which does nothing, there's not much to see
here. We can now make our own little consumer following this class' example:

```cpp
class MyDiagnosticConsumer : public clang::DiagnosticConsumer {
public:
  void HandleDiagnostic(clang::DiagnosticsEngine::Level DiagLevel,
                        const clang::Diagnostic& Info) override {
    llvm::errs() << Info.getID() << '\n';
  }
};
```

which we can then just register with the `DiagnosticsEngine` via its `setClient`
method:

```cpp
auto& DE = Context.getDiagnostics();
DE.setClient(new MyDiagnosticConsumer(), /*ShouldOwnClient=*/true);
```

To get access to the actual diagnostic string we can use
`Diagnostic::FormatDiagnostic`, which will append the formatted message (i.e.
after substitution of `%<n>` arguments) to the output buffer you provide:

```cpp
void HandleDiagnostic(clang::DiagnosticsEngine::Level DiagLevel,
                      const clang::Diagnostic& Info) override {
  llvm::SmallVector<char, 128> message;
  Info.FormatDiagnostic(message);
  llvm::errs() << message << '\n';
}
```

# FixIt Hints

The last tool in clang's diagnostics kit I'd like to talk about is *FixIt
hints*, which are low false-positive rate suggestions we can provide to the user
as to how a particular issue could be fixed. At the top of the post you can see
an example of a FixIt hint where clang suggests that a semicolon should be added
where one is missing. For the following discussion, we'll be using the following
simple snippet as a rolling example:

```cpp
int var = 4 + 2;
```

which could be matched with the following `ast_matchers` matcher:

```cpp
varDecl(
  hasType(isInteger()),
  hasInitializer(binaryOperator(
    hasOperatorName("+"),
    hasLHS(integerLiteral().bind("lhs")),
    hasRHS(integerLiteral().bind("rhs"))).bind("op"))).bind("var");
```

## Creating FixIt Hints

FixIt hints are created via various static factory functions and can then be
supplied to the `DiagnosticBuilder`, which will cause the FixIt hint to be
emitted alongside any error message we provide. More precisely, there are four
kinds of FixIt hints we can emit, each created via their respective factory
function: insertions, replacements, removals and moves (i.e. moving existing
code somewhere else). I'll discuss each in more detail in the following
paragraphs.

### Insertions

`clang::FixItHint::CreateInsertion()` takes a source location and a snippet of
code whose insertion should be suggested at the given location. Optionally, you
can specify whether the insertion should be placed before or after other
insertions at that point (the third argument), which defaults to `false`. You
could use it like so to suggest the renaming of the matched variable:

```cpp
void run(const MatchResult& Result) {
  const auto* VarDecl = Result.Nodes.getNodeAs<clang::VarDecl>("var");
  const auto FixIt = clang::FixItHint::CreateInsertion(VarDecl->getLocation(), "added_");

  auto& DE = Context.getDiagnostics();
  const auto ID = DE.getCustomDiagID(clang::DiagnosticsEngine::Remark,
                                     "Please rename this");
  DE.Report(VarDecl->GetLocation(), ID).AddFixItHint(FixIt);
}
```

Running a tool with this code on the above snippet will produce:

```shell
file.cpp:1:5: remark: Please rename this
int var = 4 + 2;
    ^
    added_
```

### Replacements

To replace code with a suggested snippet, you can use the
`clang::FixItHint::CreateReplacement()` function. It takes a source range in the
code to replace, and the snippet you want to replace it with. Let's use it to
warn that the plus should better be a minus, just for reasons:

```cpp
void run(const MatchResult& Result) {
  const auto* Op = Result.Nodes.getNodeAs<clang::BinaryOperator>("op");

  const auto Start = Op->getOperatorLoc();
  const auto End = Start.getLocWithOffset(+1);
  const auto SourceRange = clang::CharSourceRange::getCharRange(Start, End);
  const auto FixIt =
      clang::FixItHint::CreateReplacement(SourceRange, "-");

  auto& DE = Context.getDiagnostics();
  const auto ID = DE.getCustomDiagID(clang::DiagnosticsEngine::Remark,
                                     "This should probably be a minus");
  DE.Report(Start, ID).AddFixItHint(FixIt);
}
```

which produces:

```shell
file.cpp:1:11: remark: This should probably be a minus
int var = 4 + 2;
            ^
            -
```

### Removals

To suggest that a redundant or illegal range of code be removed, we can call
`clang::FixItHint::CreateRemoval()`, which takes a `CharSourceRange` (or a
`SourceRange`) and provides the user with an appropriate hint. We could use it
to ensure that all our variables are only a single character, because anything
else will be too much to type:

```cpp
void run(const MatchResult& Result) {
  const auto* VarDecl = Result.Nodes.getNodeAs<clang::VarDecl>("var");

  const auto NameLength = VarDecl->getName().size();
  if (NameLength <= 1) return;

  const auto Start = VarDecl->getLocation().getLocWithOffset(+1);
  const auto End = VarDecl->getLocation().getLocWithOffset(NameLength);
  const auto FixIt =
      clang::FixItHint::CreateRemoval(clang::SourceRange(Start, End));

  auto& DE = Context.getDiagnostics();
  const auto ID = DE.getCustomDiagID(clang::DiagnosticsEngine::Remark,
                                     "Why so readable?");
  DE.Report(VarDecl->getLocation(), ID).AddFixItHint(FixIt);
}
```

This gives us:

```shell
file.cpp:1:5: remark: Why so readable?
int var = 4 + 2;
    ^~~
```

### Moves

Finally, `CreateInsertionFromRange()` allows us to suggest that a range of
existing code should be moved somewhere else. The function takes the location
where to recommend the insertion, the original range of code to move to that
location and finally again a boolean `BeforePreviousInsertions` that defaults to
`false` and handles collisions. We can use it to suggest that the two operands
of the expression be swapped:

```cpp
void run(const MatchResult& Result) {
  const auto* Left = Result.Nodes.getNodeAs<clang::IntegerLiteral>("lhs");
  const auto* Right = Result.Nodes.getNodeAs<clang::IntegerLiteral>("rhs");

  const auto LeftRange = clang::CharSourceRange::getCharRange(
      Left->getLocStart(),
      Left->getLocEnd().getLocWithOffset(+1)
  );

  const auto RightRange = clang::CharSourceRange::getCharRange(
      Right->getLocStart(),
      Right->getLocEnd().getLocWithOffset(+1)
  );

  const auto LeftFixIt = clang::FixItHint::CreateInsertionFromRange(
      Left->getLocation(),
      RightRange
  );

  const auto RightFixIt = clang::FixItHint::CreateInsertionFromRange(
      Right->getLocation(),
      LeftRange
  );

  auto& DE = Context.getDiagnostics();
  const auto ID =
      DE.getCustomDiagID(clang::DiagnosticsEngine::Remark,
                         "Integer plus is commutative, so let's swap these");

  DE.Report(Left->getLocation(), ID).AddFixItHint(LeftFixIt);
  DE.Report(Right->getLocation(), ID).AddFixItHint(RightFixIt);
}
```

which results in the following diagnostics:

```
file.cpp:1:11: remark: Integer plus is commutative, so let's swap these
int var = 4 + 2;
          ^
          2
file.cpp:1:15: remark: Integer plus is commutative, so let's swap these
int var = 4 + 2;
              ^
              4
```

## Acting on FixIts

Often, we'll not only want to emit our FixIt hints in diagnostics, but also
provide the user the ability to act on the hints and apply them, either in-place
or by writing the resulting code to a new file. Clang has nice facilities for
this in form of the `clang::FixItRewriter`. It's reasonably simple to use, but
required quite a lot of digging through clang's source code to understand
entirely. I'll spare you from that.

Basically, the `FixItRewriter`, which you can find in
`include/clang/Rewrite/Frontend/FixItRewriter.h` and
`lib/Frontend/Rewrite/FixItRewriter.cpp` (no, the folder swap is not my typo),
is a subclass of the `clang::DiagnosticConsumer`, meaning we can register it
with our `DiagnosticsEngine` and then tell it to rewrite files. This will look
like this:

```cpp
auto& DE = Context.getDiagnostics();
OurFixItRewriterOptions Options;
clang::FixItRewriter Rewriter(DE,
                              Context->getSourceManager(),
                              Context->getLangOpts(),
                              &Options);

DE.setClient(&Rewriter, /*ShouldOwnClient=*/false);

// ...

Rewriter.WriteFixedFiles();
```

Before discussing the mysterious `OurFixItRewriterOptions` in the above code,
let me explain in a bit more detail what the `FixItRewriter` does. As it is a
`DiagnosticsConsumer` subclass, it overrides the `HandleDiagnostic` method.
Inside, it will first forward the diagnostic to *its own* client, which is the
one the `DiagnosticsEngine` has registered when you construct the
`FixItRewriter`. This means that the diagnostics we report will still be emitted
to the console as before, just that, additionally, the rewriter will do some
work on the FixIts that are registered with each `Diagnostic` passed to
`HandleDiagnostic`. This "work" looks something like this (from
`FixItRewriter.cpp`):

```cpp
edit::Commit commit(Editor);
for (unsigned Idx = 0, Last = Info.getNumFixItHints();
     Idx < Last; ++Idx) {
  const FixItHint &Hint = Info.getFixItHint(Idx);

  if (Hint.CodeToInsert.empty()) {
    if (Hint.InsertFromRange.isValid())
      commit.insertFromRange(Hint.RemoveRange.getBegin(),
                         Hint.InsertFromRange, /*afterToken=*/false,
                         Hint.BeforePreviousInsertions);
    else
      commit.remove(Hint.RemoveRange);
  } else {
    if (Hint.RemoveRange.isTokenRange() ||
        Hint.RemoveRange.getBegin() != Hint.RemoveRange.getEnd())
      commit.replace(Hint.RemoveRange, Hint.CodeToInsert);
    else
      commit.insert(Hint.RemoveRange.getBegin(), Hint.CodeToInsert,
                  /*afterToken=*/false, Hint.BeforePreviousInsertions);
  }
}
```

Besides the transaction system clang has built for its source file
modifications, what you see here is basically a loop over the FixIts registered
for the diagnostic. Each FixIt results in one commit to the source file the
FixIt references. However, these changes will *not* be performed inside
`HandleDiagnostic`. For this to happen, you must call
`FixItRewriter::WriteFixedFiles`. Inside this method, the rewriter will query
its `FixItOptions` to determine where to store the resulting source buffer. This
can be the same file for in-place changes, or a new file otherwise.

As such, what's missing from the above example is the following subclass of
`clang:FixItOptions`, which we have to define as well:

```cpp
class OurFixItRewriterOptions : public clang::FixItOptions {
 public:
  MyFixItOptions() {
    InPlace = true;
  }

  std::string RewriteFilename(const std::string& Filename, int& fd) override {
    llvm_unreachable("RewriteFilename should not be called when InPlace = true");
  }
};
```

It may seem a bit weird that a configuration object like `FixItOptions` has to
be subclassed just to set a single option. The reason for this is that one part
of the configuration is the `RewriteFilename` method, where we can dynamically
choose the name of the file a changed source buffer should be written to (it may
have been wiser to opt for simply passing a `std::function` object and sparing
us from all the boilerplate of subclassing, but that's another discussion). If
we want the changes to be applied in-place, we can simply set the
`FixItOptions`'s `InPlace` field to true. In that case, `RewriteFilename` is not
called at all. If we instead would like the changes to be stored in a new file,
we can write something like this:

```cpp

class MyFixItOptions : public clang::FixItOptions {
 public:
  MyFixItOptions() {
    InPlace = false;
    FixWhatYouCan = false;
    FixOnlyWarnings = false;
    Silent = false;
  }

  std::string RewriteFilename(const std::string& Filename, int& fd) override {
    const auto NewFilename = Filename + ".fixed";
    llvm::errs() << "Rewriting FixIts from " << Filename
                 << " to " << NewFilename
                 << "\n";
    fd = -1;
    return NewFilename;
  }
};
```

In this example, we first set `InPlace` to false and `FixWhatYouCan` to true.
The latter means that even if there are errors for some rewrites, clang should
nevertheless perform those modifications that it can (you probably wouldn't want
this in practice, it's just to show what other options exist). Furthermore, by
setting `FixOnlyWarnings` to false (its default), also errors will be fixed.
Lastly, if the `Silent` property were true, only errors or those warnings for
which FixIts were applied are forwarded to the `FixItRewriter`'s client (i.e.
diagnostics whose level is below error and that don't have a FixIt won't be
shown).

Inside `RewriteFilename`, I give an example of how you might want to store a
rewritten file with the same name, but with a `.fixed` suffix. Note that the
`fd` parameter *can* be set to an open file descriptor if you want to. In that
case, the changes will be sent to that file descriptor (maybe useful if it's a
socket?). In most cases, you'll probably just want to set it to `-1`, which
disables that functionality.

To wrap up, I'll provide you with an example of a complete clang tool that has
the option to rewrite Fixits. If we take our previous example of the plus
operation:

```cpp
// file.cpp
int x = 4 + 2;
```

And want to rewrite the plus to a minus and store the change in a file, the
following tool will do:

```cpp
// Clang includes
#include "clang/AST/ASTConsumer.h"
#include "clang/AST/ASTContext.h"
#include "clang/AST/Expr.h"
#include "clang/ASTMatchers/ASTMatchFinder.h"
#include "clang/ASTMatchers/ASTMatchers.h"
#include "clang/Basic/Diagnostic.h"
#include "clang/Basic/SourceLocation.h"
#include "clang/Frontend/FrontendAction.h"
#include "clang/Rewrite/Frontend/FixItRewriter.h"
#include "clang/Tooling/CommonOptionsParser.h"
#include "clang/Tooling/Tooling.h"

// LLVM includes
#include "llvm/ADT/ArrayRef.h"
#include "llvm/ADT/StringRef.h"
#include "llvm/Support/CommandLine.h"
#include "llvm/Support/raw_ostream.h"

// Standard includes
#include <cassert>
#include <memory>
#include <string>
#include <type_traits>

namespace MinusTool {

class FixItRewriterOptions : public clang::FixItOptions {
 public:
  using super = clang::FixItOptions;

  /// Constructor.
  ///
  /// The \p RewriteSuffix is the option from the command line.
  explicit FixItRewriterOptions(const std::string& RewriteSuffix)
  : RewriteSuffix(RewriteSuffix) {
    super::InPlace = false;
  }

  /// For a file to be rewritten, returns the (possibly) new filename.
  ///
  /// If the \c RewriteSuffix is empty, returns the \p Filename, causing
  /// in-place rewriting. If it is not empty, the \p Filename with that suffix
  /// is returned.
  std::string RewriteFilename(const std::string& Filename, int& fd) override {
    fd = -1;

    llvm::errs() << "Rewriting FixIts ";

    if (RewriteSuffix.empty()) {
      llvm::errs() << "in-place\n";
      return Filename;
    }

    const auto NewFilename = Filename + RewriteSuffix;
    llvm::errs() << "from " << Filename << " to " << NewFilename << "\n";

    return NewFilename;
  }

 private:
  /// The suffix appended to rewritten files.
  std::string RewriteSuffix;
};

class MatchHandler : public clang::ast_matchers::MatchFinder::MatchCallback {
 public:
  using MatchResult = clang::ast_matchers::MatchFinder::MatchResult;
  using RewriterPointer = std::unique_ptr<clang::FixItRewriter>;

  /// Constructor.
  ///
  /// \p DoRewrite and \p RewriteSuffix are the command line options passed
  /// to the tool.
  MatchHandler(bool DoRewrite, const std::string& RewriteSuffix)
  : FixItOptions(RewriteSuffix), DoRewrite(DoRewrite) {
  }

  /// Runs the MatchHandler's action.
  ///
  /// Emits a diagnostic for each matched expression, optionally rewriting the
  /// file in-place or to another file, depending on the command line options.
  void run(const MatchResult& Result) {
    auto& Context = *Result.Context;

    const auto& Op = Result.Nodes.getNodeAs<clang::BinaryOperator>("op");
    assert(Op != nullptr);

    const auto StartLocation = Op->getOperatorLoc();
    const auto EndLocation = StartLocation.getLocWithOffset(+1);
    const clang::SourceRange SourceRange(StartLocation, EndLocation);
    const auto FixIt = clang::FixItHint::CreateReplacement(SourceRange, "-");

    auto& DiagnosticsEngine = Context.getDiagnostics();

    // The FixItRewriter is quite a heavy object, so let's
    // not create it unless we really have to.
    RewriterPointer Rewriter;
    if (DoRewrite) {
      Rewriter = createRewriter(DiagnosticsEngine, Context);
    }

    const auto ID =
        DiagnosticsEngine.getCustomDiagID(clang::DiagnosticsEngine::Warning,
                                          "This should probably be a minus");

    DiagnosticsEngine.Report(StartLocation, ID).AddFixItHint(FixIt);

    if (DoRewrite) {
      assert(Rewriter != nullptr);
      Rewriter->WriteFixedFiles();
    }
  }

 private:
  /// Allocates a \c FixItRewriter and sets it as the client of the given \p
  /// DiagnosticsEngine.
  ///
  /// The \p Context is forwarded to the constructor of the \c FixItRewriter.
  RewriterPointer createRewriter(clang::DiagnosticsEngine& DiagnosticsEngine,
                                 clang::ASTContext& Context) {
    auto Rewriter =
        std::make_unique<clang::FixItRewriter>(DiagnosticsEngine,
                                               Context.getSourceManager(),
                                               Context.getLangOpts(),
                                               &FixItOptions);

   // Note: it would make more sense to just create a raw pointer and have the
   // DiagnosticEngine own it. However, the FixItRewriter stores a pointer to
   // the client of the DiagnosticsEngine when it gets constructed with it.
   // If we then set the rewriter to be the client of the engine, the old
   // client gets destroyed, leading to happy segfaults when the rewriter
   // handles a diagnostic.
    DiagnosticsEngine.setClient(Rewriter.get(), /*ShouldOwnClient=*/false);

    return Rewriter;
  }

  FixItRewriterOptions FixItOptions;
  bool DoRewrite;
};

/// Consumes an AST and attempts to match for the
/// kinds of nodes we are looking for.
class Consumer : public clang::ASTConsumer {
 public:
  /// Constructor.
  ///
  /// All arguments are forwarded to the \c MatchHandler.
  template <typename... Args>
  explicit Consumer(Args&&... args) : Handler(std::forward<Args>(args)...) {
    using namespace clang::ast_matchers;

    // Want to match:
    // int x = 4   +   2;
    //     ^   ^   ^   ^
    //   var  lhs op  rhs

    // clang-format off
    const auto Matcher = varDecl(
       hasType(isInteger()),
       hasInitializer(binaryOperator(
         hasOperatorName("+"),
         hasLHS(integerLiteral().bind("lhs")),
         hasRHS(integerLiteral().bind("rhs"))).bind("op"))).bind("var");
    // clang-format on

    MatchFinder.addMatcher(Matcher, &Handler);
  }

  /// Attempts to match the match expression defined in the constructor.
  void HandleTranslationUnit(clang::ASTContext& Context) override {
    MatchFinder.matchAST(Context);
  }

 private:
  /// Our callback for matches.
  MatchHandler Handler;

  /// The MatchFinder we use for matching on the AST.
  clang::ast_matchers::MatchFinder MatchFinder;
};

class Action : public clang::ASTFrontendAction {
 public:
  using ASTConsumerPointer = std::unique_ptr<clang::ASTConsumer>;

  /// Constructor, taking the \p RewriteOption and \p RewriteSuffixOption.
  Action(bool DoRewrite, const std::string& RewriteSuffix)
  : DoRewrite(DoRewrite), RewriteSuffix(RewriteSuffix) {
  }

  /// Creates the Consumer instance, forwarding the command line options.
  ASTConsumerPointer CreateASTConsumer(clang::CompilerInstance& Compiler,
                                       llvm::StringRef Filename) override {
    return std::make_unique<Consumer>(DoRewrite, RewriteSuffix);
  }

 private:
  /// Whether we want to rewrite files. Forwarded to the consumer.
  bool DoRewrite;

  /// The suffix for rewritten files. Forwarded to the consumer.
  std::string RewriteSuffix;
};
}  // namespace MinusTool

namespace {
llvm::cl::OptionCategory MinusToolCategory("minus-tool options");

llvm::cl::extrahelp MinusToolCategoryHelp(R"(
This tool turns all your plusses into minuses, because why not.
Given a binary plus operation with two integer operands:

int x = 4 + 2;

This tool will rewrite the code to change the plus into a minus:

int x = 4 - 2;

You're welcome.
)");

llvm::cl::opt<bool>
    RewriteOption("rewrite",
                  llvm::cl::init(false),
                  llvm::cl::desc("If set, emits rewritten source code"),
                  llvm::cl::cat(MinusToolCategory));

llvm::cl::opt<std::string> RewriteSuffixOption(
    "rewrite-suffix",
    llvm::cl::desc("If -rewrite is set, changes will be rewritten to a file "
                   "with the same name, but this suffix"),
    llvm::cl::cat(MinusToolCategory));

llvm::cl::extrahelp
    CommonHelp(clang::tooling::CommonOptionsParser::HelpMessage);
}  // namespace

/// A custom \c FrontendActionFactory so that we can pass the options
/// to the constructor of the tool.
struct ToolFactory : public clang::tooling::FrontendActionFactory {
  clang::FrontendAction* create() override {
    return new MinusTool::Action(RewriteOption, RewriteSuffixOption);
  }
};

auto main(int argc, const char* argv[]) -> int {
  using namespace clang::tooling;

  CommonOptionsParser OptionsParser(argc, argv, MinusToolCategory);
  ClangTool Tool(OptionsParser.getCompilations(),
                 OptionsParser.getSourcePathList());

  return Tool.run(new ToolFactory());
}
```

Does it do what we want it to?

```shell
$ ./minus-tool file.cpp -rewrite -suffix=".fixed"
file.cpp:1:11: warning: This should probably be a minus
int x = 4 + 2;
          ^
          -
file.cpp:1:11: note: FIX-IT applied suggested code changes
Rewriting FixIts from file.cpp to file.cpp.fixed
1 warning generated.

$ cat file.cpp.fixed
int x = 4 - 2;
```

# Outro

Clang is an incredibly exciting set of libraries for building not only a
full-fledged compiler, but also your own tools for static analysis, linting or
source-to-source transformation. As part of this, you'll almost always want to
emit some diagnostics, hopefully in an equally expressive manner as clang does
itself. I hope that with this post, I've shown you all you need to know about
emitting diagnostics with clang. As such, the only thing left to do is ...

<br>
![clang-all-the-things](/images/clang-diagnostics/clang-all-things.jpg)
