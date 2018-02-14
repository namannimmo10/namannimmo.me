---
layout:		post
title:		A Promenade of PyTorch
summary:	A brief discussion of a research-first deep learning framework
date:		2018-02-04 20-17-20
categories:	ml ai python
---

For the past two years, I've been quite heavily invested in
[TensorFlow](http://tensorflow.org), either [writing papers about it](https://arxiv.org/pdf/1610.01178.pdf), giving
[talks on how to extend its backend](https://www.youtube.com/watch?v=Lo1rXJdAJ7w) or [using it for my own deep learning
research](https://www.biorxiv.org/content/early/2017/12/02/227645). As part of this journey, I've gotten quite a good sense of both
TensorFlow's strong points as well as weaknesses -- or simply architectural
decisions -- that leave room for competition. That said, I have recently joined
the PyTorch team at [Facebook AI Research](https://research.fb.com/category/facebook-ai-research-fair/) (FAIR), arguably TensorFlow's biggest
competitor to date, and currently much favored in the research community for
reasons that will become apparent in subsequent paragraphs.

In this article, I want to provide a sweeping promenade of PyTorch (having given
a [tour of
TensorFlow](http://www.goldsborough.me/tensorflow/ml/ai/python/2017/06/28/20-21-45-a_sweeping_tour_of_tensorflow/)
in another blog post), shedding some light on its raîson d'être and giving an
overview of its API.

## Overview and Philosophy

Let's begin by reviewing what PyTorch is fundamentally, what programming model
it imposes on its users and how it fits into the existing deep learning
framework ecosystem:

> PyTorch is, at its core, a Python library enabling GPU-accelerated tensor computation, similar to NumPy. On top of this, PyTorch provides a rich API for neural network applications.

PyTorch differentiates itself from other machine learning frameworks in that it
does not use *static* computational graphs -- defined once, ahead of time --
like TensorFlow, [Caffe2](http://caffe2.ai) or
[MXNet](https://mxnet.apache.org). Instead, PyTorch computation graphs are
*dynamic* and *defined by run*. This means that each invocation of a PyTorch
model's layers defines a new computation graph, on the fly. The creation of this
graph is implicit, in the sense that the library takes care of recording the
flow of data through the program and linking function calls (nodes) together
(via edges) into a computation graph.

### Dynamic vs. Static Graphs

Let's go into more detail about what I mean with *static* versus *dynamic*.
Generally, in the majority of programming environments, adding two variables `x`
and `y` representing numbers produces a value containing the result of that
addition. For example, in Python:

```python
In [1]: x = 4
In [2]: y = 2
In [3]: x + y
Out[3]: 6
```

In TensorFlow, however, this is not the case. In TensorFlow, `x` and `y` would
not be numbers directly, but would instead be handles to graph nodes
*representing* those values, rather than explicitly containing them.
Furthermore, and more importantly, adding `x` and `y` would not produce the
value of the sum of these numbers, but would instead be a handle to a
computation graph, which, only when executed, produces that value:

```python
In [1]: import tensorflow as tf
In [2]: x = tf.constant(4)
In [3]: y = tf.constant(2)
In [4]: x + y
Out[4]: <tf.Tensor 'add:0' shape=() dtype=int32>
```

As such, when we write TensorFlow code, we are in fact not programming, but
*metaprogramming* -- we write a program (our code) that creates a program (the
TensorFlow computation graph). Naturally, the first programming model is much
simpler than the second. It is much simpler to speak and think in terms of
things that *are* than speak and think in terms of things that *represent
things that are*.

PyTorch's major advantage is that its execution model is much closer to the
former than the latter. At its core, PyTorch is simply regular Python, with
support for Tensor computation like NumPy, but with added GPU acceleration of
Tensor operations and, most importantly, built-in [*automatic
differentiation*](https://en.wikipedia.org/wiki/Automatic_differentiation)
(*AD*). Since the majority of contemporary machine learning algorithms rely
heavily on linear algebra datatypes (matrices and vectors) and use gradient
information to improve their estimates, these two pillars of PyTorch are
sufficient to enable arbitrary machine learning workloads.

Going back to the simple showcase above, we can see that programming in PyTorch
resembles the natural "feeling" of Python:

```python
In [1]: import torch
In [2]: x = torch.ones(1) * 4
In [3]: y = torch.ones(1) * 2
In [4]: x + y
Out[4]:
 6
[torch.FloatTensor of size 1]
```

PyTorch deviates from the basic intuition of programming in Python in one
particular way: it records the execution of the running program. That is,
PyTorch will silently "spy" on the operations you perform on its datatypes and,
behind the scenes, construct -- again -- a computation graph. This computation
graph is required for automatic differentiation, as it must walk the chain of
operations that produced a value backwards in order to compute derivatives (for
reverse mode AD). The way this computation graph, or rather the process of
assembling this computation graph, differs notably from TensorFlow or MXNet, is
that a new graph is constructed eagerly, on the fly, each time a fragment of
code is evaluated. Conversely, in Tensorflow, a computation graph is constructed
only once, by the metaprogram that is your code. Furthermore, while PyTorch will
actually walk the graph backwards dynamically each time you ask for the
derivative of a value, TensorFlow will simply inject additional nodes into the
graph that (implicitly) calculate this derivative and are evaluated like all
other nodes. This is where the distinction between dynamic and static graphs is
most apparent.

The choice of using static or dynamic computation graphs severely impacts the
ease of programming in one of these environments. The aspect it influences most
severely is *control flow*. In a static graph environment, control flow must be
represented as specialized nodes in the graph. For example, to enable branching,
Tensorflow has a `tf.cond()` operation, which takes three subgraphs as input: a
condition subgraph and two subgraphs for the `if` and `else` branches of the
conditional. Similarly, loops must be represented in TensorFlow graphs as
`tf.while()` operations, taking a `condition` and `body` subgraph as input. In a
dynamic graph setting, all this is simplified. Since graphs are traced from
Python code *as it appears* during each evaluation, control flow can be
implemented natively in the language, using `if` clauses and `while` loops as
you would for any other program. This turns awkward and unintuitive Tensorflow
code:

```python
import tensorflow as tf

x = tf.constant(2, shape=[2, 2])
w = tf.while_loop(
  lambda x: tf.reduce_sum(x) < 100,
  lambda x: tf.nn.relu(tf.square(x)),
  [x])
```

into natural and intuitive PyTorch code:

```python
import torch.nn
from torch.autograd import Variable

x = Variable(torch.ones([2, 2]) * 2)
while x.sum() < 100:
    x = torch.nn.ReLU()(x**2)
```

The benefits of dynamic graphs from an ease-of-programming perspective reach far
beyond this, of course. Simply being able to inspect intermediate values with
`print` statements (as opposed to `tf.Print()` nodes) or a debugger is already a
big plus. Of course, as much as dynamism can aid programmability, it can also
harm performance and makes it more difficult to optimize graphs. The differences
and tradeoffs between PyTorch and TensorFlow are thus much the same as the
differences and tradeoffs between a dynamic, interpreted language like Python
and a static, compiled language like C or C++. The former is easier and faster
to work with, while the latter can be transformed into more optimized artifacts.
The former is easier to use, while the latter is easier to analyze and
(therefore) optimize. It is a tradeoff between flexibility and performance.

### A Remark on PyTorch's API

A general remark I want to make about PyTorch's API, especially for neural
network computation, compared to other libraries like TensorFlow or MXNet, is
that it is quite *batteries-included*. As someone once remarked to me,
TensorFlow's API never really went beyond the "assembly level", in the sense
that it only ever provided the basic "assembly" instructions required to
construct computational graphs (addition, multiplication, pointwise functions
etc.), with a basically non-existent "standard library" for the most common
kinds of program fragments people would eventually go on to repeat thousands of
times. Instead, it relied on the community to build higher level APIs on top of
TensorFlow.

And indeed, the community did build higher level APIs. Unfortunately, however,
not just one such API, but about a dozen -- concurrently. This means that on a
bad day you could read five papers for your research and find the source code of
each of these papers to use a different "frontend" to TensorFlow. These APIs
typically have quite little in common, such that you would essentially have to
learn 5 different frameworks, not just *TensorFlow*. A few of the most popular
such APIs are:

- [Keras](https://keras.io)
- [TFLearn](https://github.com/tflearn/tflearn)
- [PrettyTensor](https://github.com/google/prettytensor)
- [TF-Slim](https://github.com/tensorflow/tensorflow/tree/master/tensorflow/contrib/slim)

PyTorch, on the other hand, already comes with the most common building blocks
required for every-day deep learning research. It essentially has a "native"
Keras-like API in its `torch.nn` package, allowing chaining of high-level neural
network modules.

### PyTorch's Place in the Ecosystem

Having explained how PyTorch differs from static graph frameworks like MXNet,
TensorFlow or Theano, let me say that PyTorch is not, in fact, unique in its
approach to neural network computation. Before PyTorch, there were already
libraries like [Chainer](https://chainer.org) or
[DyNet](https://github.com/clab/dynet) that provided a similar dynamic graph
API. Today, PyTorch is more popular than these alternatives, though.

At Facebook, PyTorch is also not the only framework in use. The majority of our
production workloads currently run on [Caffe2](https://caffe2.ai), which is a static graph
framework born out of [Caffe](http://caffe.berkeleyvision.org). To marry the flexibility PyTorch provides to
researchers with the benefits of static graphs for optimized production
purposes, Facebook is also developing [ONNX](https://onnx.ai), which is intended to be an
interchange format between PyTorch, Caffe2 and other libraries like MXNet or
[CNTK](https://www.microsoft.com/en-us/cognitive-toolkit/).

Lastly, a word on history: Before PyTorch, there was [Torch](http://torch.ch) --
a fairly old (early 2000s) scientific computing library programmed via the
[Lua](https://www.lua.org) language. Torch wraps a C codebase, making it fast
and efficient. Fundamentally, *PyTorch wraps this same C codebase* (albeit with
a [layer of abstraction in between](https://github.com/zdevito/ATen)) while
providing a Python API to its users. Let's talk about this Python API next.

## Using PyTorch

In the following paragraphs I will discuss the basic concepts and core
components of the PyTorch library, covering its fundamental datatypes, its
automatic differentiation machinery, its neural network specific functionality
as well as utilities for loading and processing data.

### Tensors

The most fundamental datatype in PyTorch is a `tensor`. The `tensor` datatype is
very similar, both in importance and function, to NumPy's `ndarray`.
Furthermore, since PyTorch aims to interoperate reasonably well with NumPy, the
API of `tensor` also *resembles* (but not *equals*) that of `ndarray`. PyTorch
tensors can be created with the `torch.Tensor` constructor, which takes the
tensor's dimensions as input and returns a tensor occupying an *uninitialized*
region of memory:

```python
import torch
x = torch.Tensor(4, 4)
```

In practice, one will most often want to use one of PyTorch's functions that return tensors initialized in a certain manner, such as:

- `torch.rand`: values initialized from a random *uniform* distribution,
- `torch.randn`: values initialized from a random *normal* distribution,
- `torch.eye(n)`: an $n \times n$ identity matrix,
- `torch.from_numpy(ndarray)`: a PyTorch tensor from a NumPy `ndarray`,
- `torch.linspace(start, end, steps)`: a 1-D tensor with `steps` values spaced linearly between `start` and `end`,
- `torch.ones` : a tensor with ones everywhere,
- `torch.zeros_like(other)` : a tensor with the same shape as `other` and zeros everywhere,
- `torch.arange(start, end, step)`: a 1-D tensor with values filled from a range.

Similar to NumPy's `ndarray`, PyTorch tensors provide a very rich API for
combination with other tensors as well as in-place mutation. Also like NumPy,
unary and binary operations can usually be performed via functions in the
`torch` module, like `torch.add(x, y)`, or directly via methods on the tensor
objects, like `x.add(y)`. For the usual suspects, operator overloads like `x +
y` exist. Furthermore, many functions have in-place alternatives that will
mutate the receiver instance rather than creating a new tensor. These functions
have the same name as the out-of-place variants, but are suffixed with an
underscore, e.g. `x.add_(y)`.

A selection of operations includes:

- `torch.add(x, y)`: elementwise addition,
- `torch.mm(x, y)`: matrix multiplication (not `matmul` or `dot`),
- `torch.mul(x, y)`: elementwise multiplication,
- `torch.exp(x)`: elementwise exponential,
- `torch.pow(x, power)`: elementwise exponentiation,
- `torch.sqrt(x)`: elementwise squaring,
- `torch.sqrt_(x)`: in-place elementwise squaring,
- `torch.sigmoid(x)`: elementwise sigmoid.
- `torch.cumprod(x)`: product of all values,
- `torch.sum(x)`: sum of all values,
- `torch.std(x)`: standard deviation of all values,
- `torch.mean(x)`: mean of all values.


Tensors support many of the familiar semantics of NumPy `ndarray`'s, such as
broadcasting, advanced (fancy) indexing (`x[x > 5]`) and elementwise relational
operators (`x > y`). PyTorch tensors can also be converted to NumPy `ndarray`'s
directly via the `torch.Tensor.numpy()` function. Finally, since the primary
improvement of PyTorch tensors over NumPy `ndarray`s is supposed to be GPU
acceleration, there is also a `torch.Tensor.cuda()` function, which will copy
the tensor memory onto a CUDA-capable GPU device, if one is available.

### Autograd

At the core of most modern machine learning techniques is the calculation of
gradients. This is especially true for neural networks, which use the
backpropagation algorithm to update weights. For this reason, Pytorch has strong
and native support for gradient computation of functions and variables defined
within the framework. The technique with which gradients are computed
automatically for arbitrary computations is called *automatic* (sometimes
*algorithmic*) *differentiation*.

Frameworks that employ the static computation graph model implement automatic
differentiation by analyzing the graph and adding additional computation nodes
to it that compute the gradient of one value with respect to another step by
step, piecing together the chain rule by linking these additional gradient nodes
with edges.

PyTorch, however, does not have static computation graphs and thus does not have
the luxury of adding gradient nodes after the rest of the computations have
already been defined. Instead, PyTorch must *record* or *trace* the flow of
values through the program as they occur, thus creating a computation graph
*dynamically*. Once such a graph is recorded, PyTorch has the information
required to walk this computation flow backwards and calculate gradients of
outputs from inputs.

The PyTorch `Tensor` *currently* does not have sufficient machinery to
participate in automatic differentiation. For a tensor to be "recordable", it
must be wrapped with `torch.autograd.Variable`. The `Variable` class provides
almost the same API as `Tensor`, but augments it with the ability to interplay
with `torch.autograd.Function` in order to be differentiated automatically. More
precisely, a `Variable` records the history of operations on a `Tensor`.

Usage of `torch.autograd.Variable` is very simple. One needs only to pass it a
`Tensor` and inform torch whether or not this variable requires recording of
gradients:

```python
x = torch.autograd.Variable(torch.ones(4, 4), requires_grad=True)
```

The `requires_grad` function may need to be `False` in the case of data inputs
or labels, for example, since those are usually not differentiated. However,
they still need to be `Variable`s to be usable in automatic differentiation.
Note that `requires_grad` defaults to `False`, thus must be set to `True` for learnable parameters.

To compute gradients and perform automatic differentiation, one calls the
`backward()` function on a `Variable`. This will compute the gradient of that
tensor with respect to the *leaves* of the computation graph (all inputs that
influenced that value). These gradients are then collected in the `Variable`
class' `grad` member:

```python
In [1]: import torch
In [2]: from torch.autograd import Variable
In [3]: x = Variable(torch.ones(1, 5))
In [4]: w = Variable(torch.randn(5, 1), requires_grad=True)
In [5]: b = Variable(torch.randn(1), requires_grad=True)
In [6]: y = x.mm(w) + b # mm = matrix multiply
In [7]: y.backward() # perform automatic differentiation
In [8]: w.grad
Out[8]:
Variable containing:
 1
 1
 1
 1
 1
[torch.FloatTensor of size (5,1)]
In [9]: b.grad
Out[9]:
Variable containing:
 1
[torch.FloatTensor of size (1,)]
In [10]: x.grad
None
```

Since every `Variable` except for inputs is the result of an operation, each
`Variable` has an associated `grad_fn`, which is the `torch.autograd.Function`
that is used to compute the backward step. For inputs it is `None`:

```python
In [11]: y.grad_fn
Out[11]: <AddBackward1 at 0x1077cef60>
In [12]: x.grad_fn
None
```

### `torch.nn`

The `torch.nn` module exposes neural-network specific functionality to PyTorch
users. One of its most important members is `torch.nn.Module`, which represents
a reusable block of operations and associated (trainable) parameters, most
commonly used for neural network layers. Modules may contain other modules and
implicitly get a `backward()` function for backpropagation. An example of a
module is `torch.nn.Linear()`, which represents a linear (dense/fully-connected)
layer (i.e. an affine transformation $Wx + b$):

```python
In [1]: import torch
In [2]: from torch import nn
In [3]: from torch.autograd import Variable
In [4]: x = Variable(torch.ones(5, 5))
In [5]: x
Out[5]:
Variable containing:
 1  1  1  1  1
 1  1  1  1  1
 1  1  1  1  1
 1  1  1  1  1
 1  1  1  1  1
[torch.FloatTensor of size (5,5)]
In [6]: linear = nn.Linear(5, 1)
In [7]: linear(x)
Out[7]:
Variable containing:
 0.3324
 0.3324
 0.3324
 0.3324
 0.3324
[torch.FloatTensor of size (5,1)]
```

During training, one will often call `backward()` on a module to compute
gradients for its variables. Since calling `backward()` sets the `grad` member
of `Variable`s, there is also a `nn.Module.zero_grad()` method that will *reset*
the `grad` member of all `Variable`s to zero. Your training loop will commonly
call `zero_grad()` at the start, or just before calling `backward()`, to reset
the gradients for the next optimization step.

When writing your own neural network models, you will often end up having to
write *your own* module subclasses to encapsulate common functionality that you
want to integrate with PyTorch. You can do this very easily, by deriving a class
from `torch.nn.Module` and giving it a `forward` method. For example, here is a
module I wrote for one of my models that adds gaussian noise to its input:

```python
class AddNoise(torch.nn.Module):
    def __init__(self, mean=0.0, stddev=0.1):
        super(AddNoise, self).__init__()
        self.mean = mean
        self.stddev = stddev

    def forward(self, input):
        noise = input.clone().normal_(self.mean, self.stddev)
        return input + noise
```

To connect or *chain* modules into full-fledged models, you can use the
`torch.nn.Sequential()` container, to which you pass a sequence of modules and
which will in turn act as a module of its own, evaluating the modules you passed
to it sequentially on each invocation. For example:

```python
In [1]: import torch
In [2]: from torch import nn
In [3]: from torch.autograd import Variable
In [4]: model = nn.Sequential(
   ...:     nn.Conv2d(1, 20, 5),
   ...:     nn.ReLU(),
   ...:     nn.Conv2d(20, 64, 5),
   ...:     nn.ReLU())
   ...:

In [5]: image = Variable(torch.rand(1, 1, 32, 32))
In [6]: model(image)
Out[6]:
Variable containing:
(0 ,0 ,.,.) =
  0.0026  0.0685  0.0000  ...   0.0000  0.1864  0.0413
  0.0000  0.0979  0.0119  ...   0.1637  0.0618  0.0000
  0.0000  0.0000  0.0000  ...   0.1289  0.1293  0.0000
           ...             ⋱             ...
  0.1006  0.1270  0.0723  ...   0.0000  0.1026  0.0000
  0.0000  0.0000  0.0574  ...   0.1491  0.0000  0.0191
  0.0150  0.0321  0.0000  ...   0.0204  0.0146  0.1724
```

#### Losses

`torch.nn` also provides a number of *loss functions* that are naturally
important to machine learning applications. Examples of loss functions include:

- `torch.nn.MSELoss`: a mean squared error loss,
- `torch.nn.BCELoss`: a binary cross entropy loss,
- `torch.nn.KLDivLoss`: a Kullback-Leibler divergence loss.

In PyTorch jargon, loss functions are often called *criterions*. Criterions are
really just simple modules that you can parameterize upon construction and then
use as plain functions from there on:

```python
In [1]: import torch
In [2]: import torch.nn
In [3]: from torch.autograd import Variable
In [4]: x = Variable(torch.randn(10, 3))
In [5]: y = Variable(torch.ones(10).type(torch.LongTensor))
In [6]: weights = Variable(torch.Tensor([0.2, 0.2, 0.6]))
In [7]: loss_function = torch.nn.CrossEntropyLoss(weight=weights)
In [8]: loss_value = loss_function(x, y)
Out [8]: Variable containing:
 1.2380
[torch.FloatTensor of size (1,)]
```

### Optimizers

After neural network building blocks (`nn.Module`) and loss functions, the last
piece of the puzzle is an *optimizer* to run (a variant of) stochastic gradient
descent. For this, PyTorch provides the `torch.optim` package, which defines a
number of common optimization algorithms, such as:

- `torch.optim.SGD`: [stochastic gradient descent](https://en.wikipedia.org/wiki/Stochastic_gradient_descent),
- `torch.optim.Adam`: [adaptive moment estimation](https://arxiv.org/pdf/1412.6980.pdf),
- `torch.optim.RMSprop`: [an algorithm developed by Geoffrey Hinton in his Coursera course](https://www.coursera.org/learn/deep-neural-network/lecture/BhJlm/rmsprop),
- `torch.optim.LBFGS`: [limited-memory Broyden–Fletcher–Goldfarb–Shanno](https://en.wikipedia.org/wiki/Limited-memory_BFGS),

Each of these optimizers are constructed with a list of parameter objects,
usually retrieved via the `parameters()` method of a `nn.Module` subclass, that
determine which values are updated by the optimizer. Besides this parameter
list, the optimizers each take a certain number of additional arguments to
configure their optimization strategy. For example:

```python
In [1]: import torch
In [2]: import torch.optim
In [3]: from torch.autograd import Variable
In [4]: x = Variable(torch.randn(5, 5))
In [5]: y = Variable(torch.randn(5, 5), requires_grad=True)
In [6]: z = x.mm(y).mean() # Perform an operation
In [7]: opt = torch.optim.Adam([y], lr=2e-4, betas=(0.5, 0.999))
In [8]: z.backward() # Calculate gradients
In [9]: y.data
Out[9]:
-0.4109 -0.0521  0.1481  1.9327  1.5276
-1.2396  0.0819 -1.3986 -0.0576  1.9694
 0.6252  0.7571 -2.2882 -0.1773  1.4825
 0.2634 -2.1945 -2.0998  0.7056  1.6744
 1.5266  1.7088  0.7706 -0.7874 -0.0161
[torch.FloatTensor of size 5x5]
In [10]: opt.step() # Update y according to Adam's gradient update rules
In [11]: y.data
Out[11]:
-0.4107 -0.0519  0.1483  1.9329  1.5278
-1.2398  0.0817 -1.3988 -0.0578  1.9692
 0.6250  0.7569 -2.2884 -0.1775  1.4823
 0.2636 -2.1943 -2.0996  0.7058  1.6746
 1.5264  1.7086  0.7704 -0.7876 -0.0163
[torch.FloatTensor of size 5x5]
```

### Data Loading

For convenience, PyTorch provides a number of utilities to load, preprocess and
interact with datasets. These helper classes and functions are found in the
`torch.utils.data` module. The two major concepts here are:

1. A `Dataset`, which encapsulates a source of data,
2. A `DataLoader`, which is responsible for loading a dataset, possibly in parallel.

New datasets are created by subclassing the `torch.utils.data.Dataset` class and
overriding the `__len__` method to return the number of samples in the dataset
and the `__getitem__` method to access a single value at a certain index. For
example, this would be a simple dataset encapsulating a range of integers:

```python
import math

class RangeDataset(torch.utils.data.Dataset):
  def __init__(self, start, end, step=1):
    self.start = start
    self.end = end
    self.step = step

  def __len__(self, length):
    return math.ceil((self.end - self.start) / self.step)

  def __getitem__(self, index):
    value = self.start + index * self.step
    assert value < self.end
    return value
```

Inside `__init__` we would usually configure some paths or change the set of
samples ultimately returned. In `__len__`, we specify the upper bound for the
index with which `__getitem__` may be called, and in `__getitem__` we return the
actual sample, which could be an image or an audio snippet.

To iterate over the dataset we could, in theory, simply have a `for i in range`
loop and access samples via `__getitem__`. However, it would be much more
convenient if the dataset implemented the iterator protocol itself, so we could
simply loop over samples with `for sample in dataset`. Fortunately, this
functionality is provided by the `DataLoader` class. A `DataLoader` object takes
a dataset and a number of options that configure the way samples are retrieved.
For example, it is possible to load samples in parallel, using multiple
processes. For this, the `DataLoader` constructor takes a `num_workers`
argument. Note that `DataLoader`s always return batches, whose size is set with
the `batch_size` parameter. Here is a simple example:

```python
dataset = RangeDataset(0, 10)
data_loader = torch.utils.data.DataLoader(
    dataset, batch_size=4, shuffle=True, num_workers=2, drop_last=True)

for i, batch in enumerate(data_loader):
  print(i, batch)
```

Here, we set `batch_size` to `4`, so returned tensors will contain exactly four
values. By passing `shuffle=True`, the index sequence with which data is
accessed is permuted, such that individual samples will be returned in random
order. We also passed `drop_last=True`, so that if the number of samples left
for the final batch of the dataset is less than the specified `batch_size`, that
batch is not returned. This ensures that all batches have the same number of
elements, which may be an invariant that we need. Finally, we specified
`num_workers` to be two, meaning data will be fetched in parallel by two
processes. Once the `DataLoader` has been created, iterating over the dataset
and thereby retrieving batches is simple and natural.

A final interesting observation I want to share is that the `DataLoader`
actually has [some reasonably sophisticated
logic](https://github.com/pytorch/pytorch/blob/master/torch/utils/data/dataloader.py#L131)
to determine how to *collate* individual samples returned from your dataset's
`__getitem__` method into a batch, as returned by the `DataLoader` during
iteration. For example, if `__getitem__` returns a dictionary, the `DataLoader`
will aggregate the values of that dictionary into a single mapping for the
entire batch, using the same keys. This means that if the `Dataset`'s
`__getitem__` returns a `dict(example=example, label=label)`, then the batch
returned by the `DataLoader` will return something like `dict(example=[example1,
example2, ...], label=[label1, label2, ...])`, i.e. unpacking the values of
indidvidual samples and re-packing them into a single key for the batch's
dictionary. To override this behavior, you can pass a function argument for the
`collate_fn` parameter to the `DataLoader` object.

Note that the [`torchvision`](https://github.com/pytorch/vision) package already
provides a number of datasets, such as `torchvision.datasets.CIFAR10`, ready to
use. The same is true for `torchaudio` and `torchtext` packages.

## Outro

At this point, you should be equipped with an understanding of both PyTorch's
philosophy as well as its basic API, and are thus ready to go forth and conquer
(PyTorch models). If this is your first exposure to PyTorch but you have
experience with other deep learning frameworks, I would recommend taking your
favorite neural network model and re-implementing it in PyTorch. For example, I
re-wrote a [TensorFlow implementation](https://github.com/goldsborough/cytogan/blob/master/playground/gan/lsgan.py) of the
[LSGAN](https://arxiv.org/abs/1611.04076) (least-squares GAN) architecture I had
lying around [in PyTorch](https://gist.github.com/goldsborough/21fb5e1167a13b49ac2a46d327bef2d7), and thus learnt the crux of using it. Further articles that may be of interest can be found [here](http://pytorch.org/tutorials/beginner/deep_learning_60min_blitz.html) and [here](http://pytorch.org/tutorials/beginner/pytorch_with_examples.html).

Summing up, PyTorch is a very exciting player in the field of deep learning
frameworks, exploiting its unique niche of being a research-first library, while
still providing the performance necessary to get the job done. Its dynamic graph
computation model is an exciting contrast to static graph frameworks like
TensorFlow or MXNet, that many will find more suitable for performing their
experiments. I sure look forward to working on it.
