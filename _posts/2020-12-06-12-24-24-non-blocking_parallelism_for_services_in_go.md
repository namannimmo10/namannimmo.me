---
layout:        post
title:        Non-Blocking Parallelism for Services in Go
summary:    a.k.a. the "tickler" pattern
date:        2020-12-06 12-24-24
categories:    go
---

Go has plenty of useful builtin functionality for safe, concurrent and parallel code. However neat those features may be, they cannot write your program for you. As is the case for many languagges, the most important morsels of knowledge are not in the features of the language, but in the well-known *patterns* that compose those features into solutions that can address frequently reoccurring problems. I'm relatively new to using Go as my daily bread-and-butter language and recently encountered a useful pattern that I thought worth sharing. I'm told that at Palantir it is called the *tickler* pattern.

## The Tickler Pattern

The tickler pattern addresses a very particular scenario:
* You have a service processing requests of some kind and looping forever,
* Calling the service should not block the caller,
* You optionally want to bound the amount of parallelism in the service, i.e. how many requests are processed at a time.

The crux of the pattern will look as follows:
* A `list.List` will represent the service's internal queue,
* We'll have the service loop forever, waiting for a signal to reconsider the contents of the queue,
* When a new request is enqueued, this signal is sent,
* When the service completes the work for a request, this signal is also sent,
* A semaphore puts a limit on the number of in-flight requests.

Let's look at the code and discuss these steps in more detail. We begin with our types:

```go
// Dummy request -- usually some Protobuf/Thrift struct
type Request int

type Service struct {
    mu         sync.Mutex
    queue      *list.List
    sema       chan int
    loopSignal chan struct{}
}
```

We'll use a channel to represent a bounded semaphore. This is perfectly idiomatic in Go, although you could also use [`sync.Semaphore`](https://godoc.org/golang.org/x/sync/semaphore) for this if you really wanted to. One of our explicit requirements for the kind of solution we wanted was that the caller shall never block when making a request. This requirement is met by the fact that we will always first enqueue a request, leaving its processing to be done asynchronously. Note that my solution will not provide a way to retrieve a response for the request.

```go
func (s *Service) EnqueueRequest(request Request) error {
    s.mu.Lock()
    defer s.mu.Unlock()
    s.queue.PushBack(request)
    log.Printf("Added request to queue with length %d\n", s.queue.Len())
    s.tickleLoop()
    return nil
}
```

We acquire a mutex for our queue since we will have multiple goroutines accessing it concurrently. We enqueue the request and then notify the loop. The last part is explained in a bit. Now that we have a way of adding requests, we can work on the code to handle the requests. Since this is a service, we'll have it loop forever waiting for new work to be done. This is also where the loop signal comes into play:

```golang
func (s *Service) loop(ctx context.Context) {
    log.Println("Starting service loop")
    for {
        select {
        case <-s.loopSignal:
            s.tryDequeue()
        case <-ctx.Done():
            log.Printf("Loop context cancelled")
            return
        }
    }
}
```

Our `loop` method will have the service loop until the `Done()` channel on a context that we pass in is fulfilled. This will allow us to shut down the service gracefully at the end of our program, or in case an error occurs. More importantly, we wait for the `loopSignal` to tell us to *reconsider the queue*. This signal is sent on one of two occasions:

1. When a new request is enqueued,
2. When we finish processing a request.

You can convince yourself that these are the only two events in the lifetime of our service at which it is necessary to consider the queue. If the service's queue is empty, enqueuing a new request tells the service to look at this new request. If a request is enqueued but it cannot be handled right away because we've reached the limit on the parallelism we configured, the only time this will change is when a request completes processing, i.e. when the semaphore is replenished by one token. 

Let's now look at `tryDequeue`, which is called whenever the loop is "tickled". Its unconfident naming stems from the fact that when `tryDequeue` is called, we:
1. Don't know whether the queue has any requests at all, since the signal could have originated from having finished processing the last in-flight request,
2. Don't know whether we have sufficient resources if there is a request in the queue.

```go
func (s *Service) tryDequeue() {
    s.mu.Lock()
    defer s.mu.Unlock()
    if s.queue.Len() == 0 {
        return
    }
    select {
    case s.sema <- 1:
        request := s.dequeue()
        log.Printf("Dequeued request %v\n", request)
        go s.process(request)
    default:
        log.Printf("Received loop signal, but request limit is reached")
    }
}

func (s *Service) dequeue() Request {
    element := s.queue.Front()
    s.queue.Remove(element)
    return element.Value.(Request)
}
```

We check for the first case of uncertainty by testing the length of the queue. If we know we have work to do, we need to check if the semaphore has sufficient slots to allow for the request to be handled. Because our semaphore `sema` will be a buffered channel, we know that if the semaphore has no slots left, sending it a new token (the integer `1`) will block, or in this case trigger the default case. If we've reached our limit on parallelism, we simply punt on handling this request until the loop is tickled anew. The `dequeue` function is a little helper that takes care of the nasty business of popping an element from the queue, which is made to involve type casting because of Go's lack of generics.

If a request passes the demanding tests of the `tryDequeue` function and is elected for processing, we take care of it in the `process` method:

```go
func (s *Service) process(request Request) {
    defer s.replenish()
    log.Printf("Processing request %v\n", request)
    // Simulate work
    <-time.After(time.Duration(rand.Intn(500)) * time.Millisecond)
}

func (s *Service) replenish() {
    <-s.sema
    log.Printf("Replenishing semaphore, now %d/%d slots in use\n", len(s.sema), cap(s.sema))
    s.tickleLoop()
}
```

What's really more interesting is the `replenish` function. This function has two responsibilities. First, it frees a slot in the semaphore so that a new request may be handled. Second, it tickles the loop to inform it that it's a good time to consider the request queue again, in case there are requests that were blocked on other requests completing first. If you recall, this is the second of two cases in which the request queue must be reconsidered.

Let's also lift the veil of mystery on the `tickleLoop` function. It simply makes a non-blocking send to the `loopSignal` channel:

```go
func (s *Service) tickleLoop() {
    select {
    case s.loopSignal <- struct{}{}:
    default:
    }
}
```

Finally, we tie everything together in the constructor of our service:

```go
func NewService(ctx context.Context, requestLimit int) *Service {
    service := &Service{
        queue:      list.New(),
        sema:       make(chan int, requestLimit),
        loopSignal: make(chan struct{}, 1),
    }
    go service.loop(ctx)
    return service
}
```

We construct `loopSignal` as a buffered channel with one free slot. If the service's loop is currently waiting for a value from the channel, a single send will tell it to reconsider the queue. If it is currently considering the queue but a request completes processing, we need to "enqueue" a signal so that when it exits `tryDequeue` and re-enters the context of the `select` statement, it knows to immediately reconsider the queue. The `sema` semaphore is a channel with sufficient buffering for the number of concurrent processing slots we wish to allow for the service. My `NewService` constructor starts the loop right away, but you could also make `Loop` a public method and do this outside of the constructor.

## Demo

A brief demonstration of our service in action is due:

```go
func main() {
    ctx, cancel := context.WithCancel(context.Background())
    defer cancel()
    service := NewService(ctx, 3)
    for i := 0; i < 10; i++ {
        if err := service.EnqueueRequest(Request(i)); err != nil {
            log.Fatalf("error sending request: %v", err)
            break
        }
        <-time.After(time.Duration(rand.Intn(100)) * time.Millisecond)
    }
    for {
        time.Sleep(time.Second)
    }
}
```

We create a cancellable context for the service that we use to signal the service to terminate its loop. For this demonstration, I bound the parallelism to three requests. The infinite loop at the end simulates running the service forever. Running this code produces the following output (out of many possible variations):

```text
2020/12/06 12:09:43 Added request to queue with length 1
2020/12/06 12:09:43 Starting service loop
2020/12/06 12:09:43 Dequeued request 0
2020/12/06 12:09:43 Processing request 0
2020/12/06 12:09:43 Replenishing semaphore, now 0/3 slots in use
2020/12/06 12:09:43 Added request to queue with length 1
2020/12/06 12:09:43 Dequeued request 1
2020/12/06 12:09:43 Processing request 1
2020/12/06 12:09:43 Added request to queue with length 1
2020/12/06 12:09:43 Dequeued request 2
2020/12/06 12:09:43 Processing request 2
2020/12/06 12:09:43 Added request to queue with length 1
2020/12/06 12:09:43 Dequeued request 3
2020/12/06 12:09:43 Processing request 3
2020/12/06 12:09:43 Replenishing semaphore, now 2/3 slots in use
2020/12/06 12:09:43 Added request to queue with length 1
2020/12/06 12:09:43 Dequeued request 4
2020/12/06 12:09:43 Processing request 4
2020/12/06 12:09:43 Replenishing semaphore, now 2/3 slots in use
2020/12/06 12:09:43 Replenishing semaphore, now 1/3 slots in use
2020/12/06 12:09:43 Added request to queue with length 1
2020/12/06 12:09:43 Dequeued request 5
2020/12/06 12:09:43 Processing request 5
2020/12/06 12:09:43 Replenishing semaphore, now 1/3 slots in use
2020/12/06 12:09:43 Added request to queue with length 1
2020/12/06 12:09:43 Dequeued request 6
2020/12/06 12:09:43 Processing request 6
2020/12/06 12:09:43 Added request to queue with length 1
2020/12/06 12:09:43 Dequeued request 7
2020/12/06 12:09:43 Processing request 7
2020/12/06 12:09:43 Replenishing semaphore, now 2/3 slots in use
2020/12/06 12:09:43 Added request to queue with length 1
2020/12/06 12:09:43 Dequeued request 8
2020/12/06 12:09:43 Processing request 8
2020/12/06 12:09:43 Replenishing semaphore, now 2/3 slots in use
2020/12/06 12:09:43 Added request to queue with length 1
2020/12/06 12:09:43 Dequeued request 9
2020/12/06 12:09:43 Processing request 9
2020/12/06 12:09:44 Replenishing semaphore, now 2/3 slots in use
2020/12/06 12:09:44 Replenishing semaphore, now 1/3 slots in use
2020/12/06 12:09:44 Replenishing semaphore, now 0/3 slots in use
```

You can observe the dance between requests being enqueued and the semaphore being replenished as requests complete. If we increase the rate at which requests are being sent by reducing the delay between calls to `service.EnqueueRequest`, we see that the queue grows quite a bit before the semaphore is replenished by a completing request:

```text
2020/12/06 12:17:58 Added request to queue with length 1
2020/12/06 12:17:58 Starting service loop
2020/12/06 12:17:58 Dequeued request 0
2020/12/06 12:17:58 Processing request 0
2020/12/06 12:17:58 Added request to queue with length 1
2020/12/06 12:17:58 Dequeued request 1
2020/12/06 12:17:58 Processing request 1
2020/12/06 12:17:58 Added request to queue with length 1
2020/12/06 12:17:58 Dequeued request 2
2020/12/06 12:17:58 Processing request 2
2020/12/06 12:17:58 Added request to queue with length 1
2020/12/06 12:17:58 Received loop signal, but request limit is reached
2020/12/06 12:17:58 Added request to queue with length 2
2020/12/06 12:17:58 Added request to queue with length 3
2020/12/06 12:17:58 Received loop signal, but request limit is reached
2020/12/06 12:17:58 Received loop signal, but request limit is reached
2020/12/06 12:17:58 Added request to queue with length 4
2020/12/06 12:17:58 Received loop signal, but request limit is reached
2020/12/06 12:17:58 Added request to queue with length 5
2020/12/06 12:17:58 Received loop signal, but request limit is reached
2020/12/06 12:17:58 Replenishing semaphore, now 2/3 slots in use
2020/12/06 12:17:58 Dequeued request 3
2020/12/06 12:17:58 Processing request 3
```

## Conclusion

And there we are -- the tickler pattern! Not the only pattern for bounded parallelism in Go, but one that addresses the constraints we set out in the beginning very well. The only scalability flaw I see with it right away is that the service could run out of memory if the rate of new requests is much greater than the rate at which requests are processed, which could grow the queue to significant lengths. This could be addressed by rejecting requests out right if the queue has reached a certain length, or rate limiting clients whose volume and frequency of requests is too demannding. If you can think of other flaws, let me know!