---
layout:		post
title:		Type Erasure for Unopinionated Interfaces in C++
summary:	Taking the ideas of std::any one step further to achieve highly flexible polymorphism
date:		2018-05-22 00-32-43
categories:	cpp
---

The life of a library designer is hard: She must make decisions about the components and interfaces
the library provides, yet leave some decisions to be made by the user. He must be opinionated, yet
leave opinions to be had by the client. She must put forward a uniform API, yet allow flexibility
for the most unforeseen use cases. For some, a library may be too minimal and provide far too
little. For others, the same library may be too restrictive and unbending. Too little salt and the
meal tastes bland, too much and it's spoiled.

To solve this dilemma between convention and configuration we often spend many hours in design
discussions with oneself or other people, trying to come up with the one true interface that will
appease both sides and suit all users and all use cases that ever will be. At an abstract level,
such design discussions are the process of taking an open "universe" of options and narrowing it
down, constraining it, shaping it into the minimal subset of the original universe that we find both
sufficiently flexible and sufficiently straightforward to use. If we think of API design as sawing a
plank of wood into a certain shape, then the "saws" of API design are *opinions*. Opinions force
constraints and assumptions on our interfaces, allowing us to reduce the scope and simplify the
design of our library.

Let me clarify my point with an example. Say we are discussing an interface for a class representing
a person -- a human being -- of which we would like to have multiple subclasses inside and outside
of our library, for different kinds of persons. At the beginning of the discussion we have an open
universe of possibilities for the nature and actions of the person:

```cpp
template<typename... Ts>
class Person {
 public:

  template<typename... Us>
  Person(Us...);

  template<typename... Vs>
  auto act(Vs...);

 protected:
  std::tuple<Ts...> state_;
};
```

We begin with a person having the ability to store any state, be created from any values, and
perform an action given any inputs. Next, we form an opinion. Given the context of our situation, we
constrain the person's state to be only their name. This reduces the universe of possible instances
of a person:

```cpp
class Person {
 public:

  template<typename... Us>
  Person(Us...);

  template<typename... Vs>
  auto act(Vs...);

 protected:
  std::string name_;
};
```

Furthermore, a person is created exclusively from their name:

```cpp
class Person {
 public:

  Person(std::string name);

  template<typename... Vs>
  auto act(Vs...);

 protected:
  std::string name_;
};
```

Finally, we decide that in our API, persons need not perform *any* possible action. They only need
one: `work`, which shall return no value:

```cpp
class Person {
 public:

  Person(std::string name);

  template<typename... Vs>
  void work(Vs...);

 protected:
  std::string name_;
};
```

At this point, we have successfully sawed persons into a more narrow representation than they had
originally -- by means of *opinions*. However, we have also reached a very difficult obstacle on the
way to finalizing our design: How do we know the way in which all persons that will ever be `work`?
Naturally, humans in modern societies don't perform only one kind of work and more importantly, the
work they perform requires very different "inputs". A cook requires ingredients and a recipe to
perform his `work`. A software engineer requires coffee, a keyboard and probably a monitor. Clearly,
we need to be flexible in the design of our `work` method.

## Traditional Polymorphism

Since we would like to have many kinds of persons, each of which have a different way of `work`ing,
we need to resort to some kind of polymorphism. The interface above cannot stand as is, since
template methods cannot be virtual in C++, thus giving us no means of customizing behavior for
different subclasses of persons. Instead, C++ provides two solutions to this situation: *dynamic* or
*static* polymorphism.

### Static Polymorphism

The *static* kind of polymorphism in C++ involves the use of templates, which is of course pleasing
to the C++ aficionado:

```cpp
// Our library

namespace Library {
class Person {
 public:
  explicit Person(std::string name) : name_(std::move(name)) { }
  const std::string& name() const noexcept { return name_; }
 protected:
  std::string name_;
};

template<typename P>
class Office {
 public:
  explicit Office(P&& person) : person_(std::move(person)) { }

  template<typename... Args>
  void work(Args&&... args) {
    std::cout << person_.name() << " is working ... " << std::endl;
    person_.work(std::forward<Args>(args)...);
  }

 private:
  P person_;
};
} // namespace Library

// User code

class Cook : public Library::Person {
 public:
  using Library::Person::Person;
  void work(Recipe recipe, const std::vector<Ingredient>& ingredients) { }
};

class SoftwareEngineer : public Library::Person {
 public:
  using Library::Person::Person;
  void work(Monitor monitor, Keyboard keyboard, Cup coffee) { }
};

auto main() -> int {
  Library::Office<Cook>(Cook("Thomas")).work(Recipe{}, std::vector<Ingredient>{});
  Library::Office<SoftwareEngineer>(SoftwareEngineer("Vanessa")).work(Monitor{}, Keyboard{}, Cup{});
}
```

Here, the inheritance between `Cook` and `Person`, and `SoftwareEngineer` and `Person`, is purely to
share code (`Person` does not even have virtual methods). At the point of use, where wish to call
different kinds of persons with different kinds of arguments, we use templates to achieve
polymorphism. Overall, this interface for the `Person` class is very flexible, as it places no
constraints on the nature of `work()`. Instead of making an opinion about the signature of `work()`,
it leaves all such opinions to the user. The `Office` class in our library expects solely that the
type it is instantiated with has a `work` method, which can be invoked with certain arguments. By
the nature of static polymorphism the interface mandated by our library is not explicit -- there are
no virtual methods to override -- but implicit. The library code using the `Person` class *becomes
the spec*.

This all sounds grand and rosy, but it is not long until we run into the drawbacks of static
polymorphism. First, the type of `Person` we place in the `Office` is fixed at compile time. We
cannot change the inhabitant of the `Office` from `Cook` to `SoftwareEngineer` at runtime. Second,
while templates are safe and fun, they simply do not scale well with large scale library design. Use
a template once and all code using the template, up to the point of actual instantiation, becomes a
template. Your library becomes a header only library, and you spend too much of your time fighting
nasty compiler errors because you missed an angle bracket in a lengthy `enable_if` expression. If
you are fine with going full template in your library, static polymorphism is just great. If not,
you will want to investigate the alternatives discussed below.

### Dynamic Polymorphism

The second form of polymorphism strikes a different balance between flexibility and constraint:
*dynamic polymorphism*. When we employ dynamic polymorphism, we give the base class a virtual method
that subclasses must implement. As can be deduced from its name, this approach gives us more
flexibility at runtime. Given a pointer to the base class, we can change the dynamic type it points
to at runtime with ease. Our library also need not be header only. There are performance
implications I'm sure you're aware of, but I will disregard these in this discussion.

The more important ramification of dynamic polymorphism in the context of this article is that it
forces us to form an uncompromising opinion about the interface of our library. We not only have to
decide that a `Person` must be able to do `work()`, but in addition must set in stone the exact
inputs and outputs a person's `work()` requires and produces. Compared to templates, this greatly
reduces the leeway of our interface. If we really, absolutely, positively must be able to give
`work()` to an arbitrary `Person*`, the best we can do is pass a `vector` of `string` to the person,
and hope she can look up what she needs in some string table, somewhere.

```cpp
namespace Library {
class Person {
 public:
  explicit Person(std::string name) : name_(std::move(name)) { }
  virtual ~Person() = default;

  const std::string& name() const noexcept { return name_; }
  virtual void work(const std::vector<std::string>& inputs) = 0;

 protected:
  std::string name_;
};

class Office {
 public:
  explicit Office(std::unique_ptr<Person>&& person) : person_(std::move(person)) { }

  void work(const std::vector<std::string>& inputs) {
    std::cout << person_->name() << " is working ... " << std::endl;
    person_->work(inputs);
  }

 private:
  std::unique_ptr<Person> person_;
};
} // namespace Library

class Cook : public Library::Person {
 public:
  using Library::Person::Person;
  void work(const std::vector<std::string>& inputs) override { }
};

class SoftwareEngineer : public Library::Person {
 public:
  using Library::Person::Person;
  void work(const std::vector<std::string>& inputs) override { }
};

auto main() -> int {
  Library::Office(std::make_unique<Cook>("Thomas")).work({"recipe_name", "vanilla", "sugar"});
  Library::Office(std::make_unique<SoftwareEngineer>("Vanessa")).work({"dell", "daskeyboard", "espresso"});
}
```

## Type Erasure: A New Hope

We have thus far discussed the two elementary kinds of polymorphism offered to us by the C++
language and its mature body of idioms and patterns. The first -- of static nature -- gave us great
flexibility in our interface, but curbed our options at runtime as well as our freedom of code
organization. The second --- the dynamic type --- alleviated the problems of the first, but forced
us to place harsh restrictions on the virtual methods of our API. What if there was a way to get the
best of both; have our cake, and eat it too?

For this I want to examine a third approach to polymorphism: one based on *type erasure*. In this
approach, we will achieve a form of dynamic polymorphism that does not restrict the interface in any
way. However, it will move certain securities C++ habitually guarantees at compile time to runtime
instead. So we'll have our cake and eat it too, but only if we agree to eat the cake over a shark
pit. Alas, [there's no free lunch](https://en.wikipedia.org/wiki/No_free_lunch_theorem). Note that
this method is based on dynamic polymorphism at the root, but the way it influences our library
design is very different.

At the foundation of this mechanism lies a little type called `Any`. You can imagine `Any` as a
black box that can store anything at any time. What's special about `Any` is that you can only
extract its content if you already know what's inside. There's nothing on the outside to indicate
what is inside the box, and if you ask for something other than what is actually stored, the `Any`
will squawk at you (i.e. throw an exception). If you do know the nature of what inhabits the `Any`,
it will happily reveal itself to you.

As you may or may not know, `Any` has an evil counterpart called `void*`. In comparison to `Any`,
`void*` is more like radioactive slime. It will take any shape you want it to, but it will probably
also kill you sooner or later.

Having introduced `Any` and its relatives, let's take a look at a very basic implementation. C++17
and Boost provide official and complete implementations in
[`std::any`](https://en.cppreference.com/w/cpp/utility/any) and
[`boost::any`](https://www.boost.org/doc/libs/1_67_0/doc/html/any.html), but it is worth
understanding its implementation for educational purposes, as well as cases where neither of these
libraries are available to you and require minimal wheel reinvention.

```cpp
#include <memory>
#include <type_traits>
#include <typeindex>
#include <typeinfo>
#include <utility>

class Any {
 public:
  template <typename T>
  /* implicit */ Any(T&& value)
  : content_(std::make_unique<Holder<T>>(std::forward<T>(value))) {}

  template <typename T>
  T& get() {
    if (std::type_index(typeid(T)) == std::type_index(content_->type_info())) {
      return static_cast<Holder<T>&>(*content_).value_;
    }
    throw std::bad_cast();
  }

 private:
  struct Placeholder {
    virtual ~Placeholder() = default;
    virtual const std::type_info& type_info() const = 0;
  };

  template <typename T>
  struct Holder : public Placeholder {
    template <typename U>
    explicit Holder(U&& value) : value_(std::forward<U>(value)) {}
    const std::type_info& type_info() const override { return typeid(T); }
    T value_;
  };

  std::unique_ptr<Placeholder> content_;
};
```

and a small usage example:

`Input`:
```cpp
Any any = 5;
std::cout << any.get<int>() << std::endl;
any = std::string("hello");
std::cout << any.get<std::string>() << std::endl;
```

`Output`:
```
5
hello
```

The fundamental idea behind `Any` is to hide an object behind a pointer, much like `void*`, but
retain type information in order to verify that the type you are asking for when accessing the `Any`
is actually correct. This type information is provided by C++'s *runtime type information* (RTTI)
system, although there exist implementations that avoid this. Upon access, we compare the type
signature of the requested type with the stored type information, and perform a safe downcast if the
types match.

The relationship between the `Placeholder` and the `Holder` is such that the `Placeholder` must
provide a virtual interface for all actions we wish to perform on the contained value when the
concrete type is not available. The `Holder` must implement this virtual interface for the concrete
type and value, of which it has full knowledge. For example, a common addition to `Any` is the
ability to copy, which is implemented in the following snippet:

```cpp
class Any {
 public:
   // Disable the constructor for `Any`, otherwise trying to copy a
   // non-const `Any` actually constructs an `Any` containing an `Any`.
  template <
      typename T,
      typename = std::enable_if_t<!std::is_same<Any, std::decay_t<T>>::value>>
  /* implicit */ Any(T&& value)
  : content_(std::make_unique<Holder<T>>(std::forward<T>(value))) {}

  // We use Scott Meyer's copy-and-swap idiom to implement special member functions.

  // `clone()` gives us a way to copy-construct a value through a type-agnostic virtual interface.
  Any(const Any& other) : content_(other.content_->clone()) {}
  Any(Any&& other) noexcept { swap(other); }
  Any& operator=(Any other) {
    swap(other);
    return *this;
  }
  void swap(Any& other) noexcept { content_.swap(other.content_); }
  ~Any() = default;

  template <typename T>
  T& get() {
    if (std::type_index(typeid(T)) == std::type_index(content_->type_info())) {
      return static_cast<Holder<T>&>(*content_).value_;
    }
    throw std::bad_cast();
  }

 private:
  struct Placeholder {
    virtual ~Placeholder() = default;
    virtual const std::type_info& type_info() const = 0;
    virtual std::unique_ptr<Placeholder> clone() = 0;
  };

  template <typename T>
  struct Holder : public Placeholder {
    template <typename U>
    explicit Holder(U&& value) : value_(std::forward<U>(value)) {}
    const std::type_info& type_info() const override { return typeid(T); }
    std::unique_ptr<Placeholder> clone() override {
      return std::make_unique<Holder<T>>(value_);
    }
    T value_;
  };

  std::unique_ptr<Placeholder> content_;
};
```

which gives `Any` the usual value semantics:

```cpp
Any a = 5;
assert(a.get<int>() == 5); // ok
Any b = a;
assert(b.get<int>() == 5); // ok
// Ensure these are actually distinct objects.
assert(&a.get<int>() != &b.get<int>()); // ok
```

### `AnyPerson`

Our little `Any` class will be very important in the further discussion of our third kind of
polymorphism, as it both forms the foundation of our polymorphic interface, as well as being one of
the basic building blocks thereof. Going back to our original problem of giving different persons of
different qualities different kinds of inputs to their work, what we can do at this stage is store
arbitrary persons inside an `Any`. This covers the functionality provided to us by static and
dynamic polymorphism related to storing concrete objects of different type. Furthermore, since `Any`
is fundamentally based on dynamic polymorphism, we also have the ability to change the contents of
an `Any` at runtime, which template based polymorphism disallowed. However, dynamic and static
polymorphism allow heterogeneity not only with regards to storage, but also with regards to
behavior. While we may store different kinds of `Person`'s in an `Any`, we currently have no means
of invoking their behavior, and letting them each do their own `work()`.

Let us break this problem down. We wish to abstract over a family of `Person`'s, each with a
`work()` method, expecting values of different types. We have in `Any` currently a way of
abstracting over a single type. So what if we simply stored each argument in an `Any`? We could then
provide a class `AnyPerson`, which would be just like `Any`, but also provides a `work()` method
that performs the magic trick of placing each argument into an `Any` box, and revealing it therefrom
when passing it on to an actual `Person`.

We begin with an `AnyPerson` class exactly identical to our previous `Any` implementation, minus a
different `enable_if` guard for the constructor:

```cpp
class AnyPerson {
 public:
  template<
    typename P,
    typename = std::enable_if_t<std::is_base_of<Library::Person, std::decay_t<P>>::value>>
  /* implicit */ AnyPerson(P&& person)
  : content_(std::make_unique<Holder<P>>(std::forward<P>(person))) {}

  AnyPerson(const AnyPerson& other) : content_(other.content_->clone()) { }
  AnyPerson(AnyPerson&& other) noexcept { swap(other); }
  AnyPerson& operator=(AnyPerson other) { swap(other); return *this; }
  void swap(AnyPerson& other) noexcept { content_.swap(other.content_); }
  ~AnyPerson() = default;

  template<typename P>
  P& get() {
    if (std::type_index(typeid(P)) == std::type_index(content_->type_info())) {
      return static_cast<Holder<P>&>(*content_).value_;
    }
    throw std::bad_cast();
  }

 private:
  struct Placeholder {
    virtual ~Placeholder() = default;
    virtual const std::type_info& type_info() const = 0;
    virtual std::unique_ptr<Placeholder> clone() = 0;
  };

  template<typename P>
  struct Holder : public Placeholder {
    template<typename Q>
    explicit Holder(Q&& person) : person_(std::forward<Q>(person)) { }
    const std::type_info& type_info() const override { return typeid(P); }
    std::unique_ptr<Placeholder> clone() override {
      return std::make_unique<Holder<P>>(person_);
    }
    P person_;
  };

  std::unique_ptr<Placeholder> content_;
};
```

and now add (most of) the necessary bits to abstract over the `work()` method:

```cpp
namespace detail {
void collect_any_vector(std::vector<Any>&) { }

template<typename Head, typename... Tail>
void collect_any_vector(std::vector<Any>& vector, Head&& head, Tail&&... tail) {
  vector.push_back(std::forward<Head>(head));
  collect_any_vector(vector, std::forward<Tail>(tail)...);
}
} // namespace detail

class AnyPerson {
 public:
  template<
    typename P,
    typename = std::enable_if_t<std::is_base_of<Library::Person, std::decay_t<P>>::value>>
  /* implicit */ AnyPerson(P&& person)
  : content_(std::make_unique<Holder<P>>(std::forward<P>(person))) {}

  // copy/move constructors

  template<typename... Args>
  void work(Args&&... arguments) {
    std::vector<Any> any_arguments;
    // replace collect_any_vector with fold expression in C++17.
    detail::collect_any_vector(any_arguments, std::forward<Args>(arguments)...);
    return content_->invoke_work(std::move(any_arguments));
  }

  template<typename P>
  P& get() {
    if (std::type_index(typeid(P)) == std::type_index(content_->type_info())) {
      return static_cast<Holder<P>&>(*content_).value_;
    }
    throw std::bad_cast();
  }

 private:
  struct Placeholder {
    virtual ~Placeholder() = default;
    virtual const std::type_info& type_info() const = 0;
    virtual std::unique_ptr<Placeholder> clone() = 0;
    virtual void invoke_work(std::vector<Any>&& arguments) = 0;  // new!
  };

  template<typename P, typename... Args>
  struct Holder : public Placeholder {
    template<typename Q>
    explicit Holder(Q&& person) : person_(std::forward<Q>(person)) { }

    const std::type_info& type_info() const override { return typeid(P); }

    std::unique_ptr<Placeholder> clone() override {
      return std::make_unique<Holder<P>>(person_);
    }

    void invoke_work(std::vector<Any>&& arguments) override {
      assert(arguments.size() == sizeof...(Args));
      invoke_work(std::move(arguments), std::make_index_sequence<sizeof...(Args)>());
    }

    template<size_t... Is>
    void invoke_work(std::vector<Any>&& arguments, std::index_sequence<Is...>) {
      // Expand the index sequence to access each `Any` stored in `arguments`,
      // and cast to the type expected at each index. Also note we move each
      // value out of the `Any`.
      return person_.work(std::move(arguments[Is].get<Args>())...);
    }

    P person_;
  };

  std::unique_ptr<Placeholder> content_;
};
```

The first step was to add a variadic `work()` method to `AnyPerson`. Making the method variadic
allows us to hide the fact that we type erase each argument when transferring it to the concrete
`Person` class, making our implementation quite transparent to the user and the call site. This type
erasure process happens in `detail::collect_any_vector`, which turns each concrete value from the
variadic argument list into an `Any`, and collects it into a `std::vector<Any>`. This vector is then
passed on to `Placeholder::invoke_work`. As I explained earlier, the contract between `Placeholder`
and `Holder` is such that for every method we wish to invoke on a concrete type, we must add a
virtual method to `Placeholder`, which the `Holder` is then required to implement. According to this
contract, we added an `invoke_work` method to `Placeholder` and `Holder`, which -- in brief --
accesses each `Any` argument, casts it to the *expected* type, and collectively forwards all the --
once again -- concrete arguments to the underlying person.

A question mark that is still bouncing here is how we ever gained knowledge about the *expected*
type of each argument? Fundamentally, this answer is along the same lines as how we have knowledge
of the concrete type of a `Person`: We infer the types upon construction of the `Any`, erase them in
the type of the concrete `Holder` instance, and access them agnostically via the `Placeholder`. The
implementation of this is currently left out of the above implementation, so we can figure out how
to add it now. Let's abstract this. I have a method `f` of some class `C`, and I want to infer the
return and argument types of this method. How about:

```cpp
template<typename C, typename R, typename... Args>
struct MethodTraits {
  using ClassType = C;
  using ReturnType = R;
  using ArgumentTypes = std::tuple<Args...>;
};

template<typename C, typename R, typename... Args>
MethodTraits<C, R, Args...> infer_method_traits(R(C::*)(Args...)) {
  return {};
}

struct C {
  double f(std::string s, int* i, float f) { return f; }
};

auto main() -> int {
  auto traits = infer_method_traits(&C::f);
}
```

Yeah. Not that hard. We can now marry this general method of inferring method argument types with
our `AnyPerson` class. The constructor becomes:

```cpp
template<
    typename P,
    typename = std::enable_if_t<std::is_base_of<Library::Person, std::decay_t<P>>::value>>
  /* implicit */ AnyPerson(P&& person)
  : content_(make_holder(std::forward<P>(person), &std::remove_reference_t<P>::work)) {}
```

and `make_holder` is simply

```cpp
template<typename P, typename C, typename... Args>
std::unique_ptr<Placeholder> make_holder(P&& person, void(std::remove_reference_t<P>::*)(Args...)) {
  return std::make_unique<Holder<P, Args...>>(std::forward<P>(person));
}
```

and this does the trick! We infer the types of the arguments to the `Person`'s `work()` method,
store them in the type of the `Holder` and erase this type by storing it in a
`std::unique_ptr<Placeholder>`. Later on, inside `invoke_work`, we then use these argument types to
regain concrete values for arguments passed by the user. What is minimally different from the toy
example of inferring method argument types is that we don't infer the type `C` of the class. This is
because we already know that this type is `P`, since we pass the method to `make_holder` as
`&P::work`. To make this succeed in all cases, we must remove any reference components to this type
`P` when inferring the method type.

We can now use `AnyPerson` in place of `std::unique_ptr<Person>` inside the `Office` class from
our dynamic polymorphism example. Before that, let's also add support for asking a `Person` for his
or her `name()`, and complete the implementation of `AnyPerson`:

```cpp
class AnyPerson {
 public:
  template<
    typename P,
    typename = std::enable_if_t<std::is_base_of<Library::Person, std::decay_t<P>>::value>>
  /* implicit */ AnyPerson(P&& person)
    : content_(make_holder(std::forward<P>(person), &std::remove_reference_t<P>::work)) {}

  AnyPerson(const AnyPerson& other) : content_(other.content_->clone()) { }
  AnyPerson(AnyPerson&& other) noexcept { swap(other); }
  AnyPerson& operator=(AnyPerson other) { swap(other); return *this; }
  void swap(AnyPerson& other) noexcept { content_.swap(other.content_); }
  ~AnyPerson() = default;

  template<typename... Args>
  void work(Args&&... arguments) {
    std::vector<Any> any_arguments;
    // replace collect_any_vector with fold expression in C++17.
    detail::collect_any_vector(any_arguments, std::forward<Args>(arguments)...);
    return content_->invoke_work(std::move(any_arguments));
  }

  const std::string& name() const noexcept {
    return content_->name();
  }

  template<typename P>
  P& get() {
    if (std::type_index(typeid(P)) == std::type_index(content_->type_info())) {
      return static_cast<Holder<P>&>(*content_).value_;
    }
    throw std::bad_cast();
  }

 private:
  struct Placeholder {
    virtual ~Placeholder() = default;
    virtual const std::type_info& type_info() const = 0;
    virtual std::unique_ptr<Placeholder> clone() = 0;
    virtual const std::string& name() const noexcept = 0;
    virtual void invoke_work(std::vector<Any>&& arguments) = 0;
  };

  template<typename P, typename... Args>
  struct Holder : public Placeholder {
    template<typename Q>
    explicit Holder(Q&& person) : person_(std::forward<Q>(person)) { }

    const std::type_info& type_info() const override { return typeid(P); }

    std::unique_ptr<Placeholder> clone() override {
      return std::make_unique<Holder<P, Args...>>(person_);
    }

    const std::string& name() const noexcept override {
      return person_.name();
    }

    void invoke_work(std::vector<Any>&& arguments) override {
      assert(arguments.size() == sizeof...(Args));
      invoke_work(std::move(arguments), std::make_index_sequence<sizeof...(Args)>());
    }

    template<size_t... Is>
    void invoke_work(std::vector<Any>&& arguments, std::index_sequence<Is...>) {
      // Expand the index sequence to access each `Any` stored in `arguments`,
      // and cast to the type expected at each index. Also note we move each
      // value out of the `Any`.
      return person_.work(std::move(arguments[Is].get<Args>())...);
    }

    P person_;
  };

  template<typename P, typename... Args>
  std::unique_ptr<Placeholder> make_holder(P&& person, void(std::remove_reference_t<P>::*)(Args...)) {
    return std::make_unique<Holder<P, Args...>>(std::forward<P>(person));
  }

  std::unique_ptr<Placeholder> content_;
};
```

At this point, let me mention three minor implementation details:
1. The `Holder` and `Placeholder` classes of `AnyPerson` could inherit from those in `Any`, for code sharing purposes;
2. The `Any` class used to transfer arguments from `AnyPerson` to concrete `Person` classes does not need copy/cloning functionality. Move is sufficient;
3. For this particular situation, where `work()` returns `void`, we did not have to deal with return types. Adding support for arbitrary return types follows much the same pattern as support for arbitrary argument types. It is a useful exercise to add support for this to the above class.

Now, we are ready to use `AnyPerson` productively:

```cpp
namespace Library {
class Person {
 public:
  explicit Person(std::string name) : name_(std::move(name)) { }
  virtual ~Person() = default;
  const std::string& name() const noexcept { return name_; }

  // no virtual work() method!

 protected:
  std::string name_;
};

class Office {
 public:
  explicit Office(AnyPerson person) : person_(std::move(person)) { }

  template<typename... Args>
  void work(Args&&... args) {
    std::cout << person_.name() << " is working ... " << std::endl;
    person_.work(std::forward<Args>(args)...);
  }

 private:
  AnyPerson person_;
};
} // namespace Library

class Cook : public Library::Person {
 public:
  using Library::Person::Person;
  void work(Recipe recipe, const std::vector<Ingredient>& ingredients) { }
};

class SoftwareEngineer : public Library::Person {
 public:
  using Library::Person::Person;
  void work(Monitor monitor, Keyboard keyboard, Cup coffee) { }
};

auto main() -> int {
  Library::Office{Cook("Thomas")}.work(Recipe{}, std::vector<Ingredient>{});
  Library::Office{SoftwareEngineer("Vanessa")}.work(Monitor{}, Keyboard{}, Cup{});
}
```

and it compiles and runs! What is important to notice here is that the `Person` base class has no
virtual `work()` method, thus placing no constraints on the signatures of its subclasses' `work()`
methods. This is the same, crucial property provided to us by static polymorphism. However, we
*still* get the ability to change the value stored in the `Office` at runtime, and do not have to
modify the location and organization of our code and force templates on our users, which were both
advantages of dynamic polymorphism! In terms of interface design, we seem to have the best of both
worlds! This mechanism gives us an extremely low friction way of providing flexibility in our
interface and rids us of the necessity to form an opinion on the nature of `work()`, instead
transferring this freedom to the user.

#### Drawbacks

Naturally, there are downsides to this design. The primary drawback is that verification of argument
types is moved to runtime instead of compile team. This is especially annoying since implicit
conversions do not work either, such that passing an `int` where a `long` is expected will result in
a runtime exception. Furthermore, also the number of arguments can only at runtime be compared to
the arity of the method. Finally, since the statically known number of arguments (`sizeof...(Args)`)
given to `AnyPerson::work` is lost while passing through `Placeholder::invoke_work`, we *must*
expect the number of arguments to be equal to the arity of the concrete `work()` method. This means
default arguments do not work out of the box. However, a scheme using `std::optional` could be
imagined, where missing arguments are filled in with `std::nullopt`.

## Outro

Assuming you did not take a 200 year lunch break between the beginning of this article and now (I
expect library design to be automated by then, where AI systems find provably optimal interfaces),
the proposition I began this article with is likely still true now: the life of a library designer
is hard and the tradeoffs she is forced to make when crafting interfaces are non-trivial. The C++
language makes this no easier, providing two "native" ways of achieving polymorphism of which
neither is perfect, both placing a hefty burden on the appearance and ergonomics of a library.

This article discussed a third means of polymorphism, based on type erasure, enabling unopinionated
interface design. It strikes a reasonable balance between the benefits of traditional polymorphism,
providing the advantages of dynamic polymorphism without the constraints it places on method
signatures and the merits of static polymorphism without the intrusion into code organization. The
price we pay for this is static type safety, instead replaced by dynamic type verification. Since
compile time safety is one of the primary selling points of C++ besides its high performance, this
is undoubtedly a steep cost. At the same time, there are equally without doubt circumstances where
interface freedom outweighs static safety. As such, I recommend adding polymorphism based on type
erasure as outlined in this article to your collection of design patterns, and employing it when the
conditions are suitable.
