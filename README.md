# Joinery
We're going to build a service that does joins between socrata datasets in a naive way


### Starting a new project
Run `mix new joinery`. This will make a elixir project with all the things you need
to get started. `cd` into the directory, run `mix test`, and everything should pass.

### Adding a dependency
The project definition lives in your `mix.exs` file in your project root, also known
as your mixfile. This defines the project structure, dependencies, as well as the OTP application.

We're going to use the Elixir Soda2 wrapper library to make SoQL queries. It's available
on [Hex.pm](https://hex.pm), so you can add it to your project by putting `{:exsoda, "~> 1.0"}` in your `deps` function, which returns a list of dependencies.

Your `deps/0` function should look like this now

```elixir
  defp deps do
    [{:exsoda, "~> 1.0"}]
  end
```

Now you can run `mix deps.get` and it should resolve the dependencies.

### The goal
We want to build an http service that can take two four-fours, get their rows, join them on some attribute, and write the result to the socket as they are fetched. To do a join, we'll do a [sort-merge-join](https://en.wikipedia.org/wiki/Sort-merge_join), and
make the soda2 store sort the rows for us. This way, we can advance through the rows in a sorted manner without loading much into memory.

### Testing and writing the Soda2 pager
First we'll need to get the rows out of the soda store. Because we don't want to
load all the rows into memory and we don't want long lived connections, we'll need to request batches of rows, which will imply some sort of state living somewhere. In Elixir/Erlang, all state is explicitly held by processes. This means the only way you can get at the state is by sending a message to that process. Because a process can only read one message at a time, this ensures that access to state is synchronized.

The idea behind state in elixir is to have a function recursively call itself, where the body of the function executes a `receive` block to handle a message in its mailbox. The function can then react to that message in any way it wants, and then it can call itself with the new state, causing it to wait for the next message.

Let's start by making a module called `Joinery.Pager` in `joinery/pager.ex` and a test module called `test/pager_test.exs`

```elixir
defmodule Joinery.Pager do
  import Exsoda.Reader
end
```

Our `Pager` module is going to have just two external functions, `start/3` and `next/3`. `start` will take the four-four, row ordering, and page size, and it will start a new process which will accept messages and then call itself recursively. `next/1` will take the pid of that process and will send a message to advance the page, then wait for a reply with the rows that it got.

We can write some really simple tests like this
```elixir
defmodule PagerTest do
  use ExUnit.Case
  alias Joinery.Pager

  test "can get the first page" do
    # Yep we're testing on live datasets - not a great
    # idea, but if this call fails then we all probably
    # have much more important stuff to be dealing with
    # right now anyway...
    {:ok, pager_pid} = Pager.start("6gnm-7jex", 5)

    {:ok, rows} = Pager.next(pager_pid, "make")
    assert length(rows) == 5
  end

  test "can get the second page" do
    {:ok, lil_pager} = Pager.start("6gnm-7jex", 5)

    {:ok, first} = Pager.next(lil_pager, "make")
    {:ok, second} = Pager.next(lil_pager, "make")

    {:ok, big_pager} = Pager.start("6gnm-7jex", 10)
    {:ok, all} = Pager.next(big_pager, "make")

    # Assert that the first two 5 item pages equal one 10 item page
    assert (first ++ second) == all
  end
end
```


Now back in our `joinery/pager.ex` `Pager` module we can start writing
the `start/3` function
```elixir
defmodule Joinery.Pager do
  import Exsoda.Reader

  def start(fourfour, order, page_size \\ 20) do
    count_response = query(fourfour)
    |> select(["count(*)"])
    |> run

    with {:ok, stream} <- count_response do
      [[{"count", c}]] = Enum.into(stream, [])
      row_count = String.to_integer(c)
      pid = spawn_link(Joinery.Pager, :handle_fetches, [fourfour, order, row_count, page_size, 0])
      {:ok, pid}
    end
  end
end
```
There's a lot going on here.
* `start/3` queries the four-four for the count of rows.
* The `with` expression only executes what's in the `do` if the `{:ok, stream}` pattern matches, otherwise it returns the non-matched pattern
* We then force the exsoda stream into a list, and take the first and only row out of it, and then turn that count into an integer.
* Then we use `spawn_link/3` to start a new process. `spawn_link/3` takes a module, a function name, and arguments to call the function with, and calls that function in a new process, returning its pid.
* `start/3` then puts the pid in an `{:ok, pid}` tuple and returns it.

So now we need to define `handle_fetches/5` which we call. This function will wait for messages and react to them, which means its body will look something like this...

```elixir
def handle_fetches(fourfour, order, row_count, page_size, current_page) do
  receive do
    some_message ->
      # do some stuff, make a new_state
      handle_fetches(fourfour, order, row_count, page_size, new_page)
  end
end

```

So now we can decide what our message format is going to look like. The tuple `{:fetch_next, sender_pid}` makes sense to me, so let's write that
```elixir
def handle_fetches(fourfour, order, row_count, page_size, current_page) do
  receive do
    {:fetch_next, sender_pid} ->
      # Now we recursively call ourselves with the incremented page
      new_page = current_page + 1
      handle_fetches(fourfour, order, row_count, page_size, new_page)
    other ->
      IO.puts("Pager got an unknown message #{inspect other}")

      # We don't know what to do with that message, so
      # the state won't change
      handle_fetches(fourfour, order, row_count, page_size, current_page)
  end
end
```
notice that we also handle other messages that we don't recognize, but we don't modify our state in any way

We also know that when the `current_page * page_size` is greater than the `row_count` our pager should be done. So we can write our termination case for our recursive function like this
```elixir
def handle_fetches(fourfour, _, row_count, page_size, current_page) when current_page * page_size >= row_count do
  IO.puts "Pager for #{fourfour} has been exhausted, exiting..."
  :done
end

# Our other definitions for handle_fetches/5 must live AFTER
# this function head
```
Since elixir pattern matches from top to bottom of the module, we need to define this function before our receive case. It will only execute when the `when` guard is satisfied. This functino doesn't call itself, so when it termintes, the process terminates as well.

Now we'll write the `next/1` function, which will advance the pager and get the page of results. It will probably look something like this.
```elixir
def next(pid) do
  # Send a message to pid, along with self() which gets the caller's pid
  # Sending the caller's pid will allow the receiving process to send us a
  # message back.
  send pid, {:fetch_next, self()}

  # Now we block until we get the message we expect, but after 5000ms
  # we give up and return an error tuple.
  receive do
    {:fetched, result} -> result
  after
    2000 -> {:error, :timeout}
  end
end

```

So now we have enough to actually run the test suite and get some failures. We should see timeouts in the `next` function because we're never actually sending it anything in response to the `{:fetch_next, self()}` message we're sending it.

Let's implement that bit. In the `handle_fetches` function that does the receive, let's do something like this:
```elixir
def handle_fetches(fourfour, order, row_count, page_size, current_page) do
  receive do
    {:fetch_next, sender_pid} ->

      # Query the four-four with an order, offset, and limit
      response = query(fourfour)
      |> order(order)
      |> offset(page_size * current_page)
      |> limit(page_size)
      |> run

      # The result of this expression is what we actually
      # care about sending to our caller
      result = case response do
        {:ok, stream} -> {:ok, Enum.into(stream, [])}
        {:error, _} = e -> e
      end

      # Because the caller very helpfully sent along their pid,
      # we can send them a message back!
      send sender_pid, {:fetched, result}

      # Now we recursively call ourselves with the incremented page,
      # which will block until we receive another message. This is a
      # little-server-state-machine-as-a-function thing. Cool!
      new_page = current_page + 1
      handle_fetches(fourfour, order, row_count, page_size, new_page)
    other ->
      IO.puts("Pager got an unknown message #{inspect other}")

      # We don't know what to do with that message, so
      # the state won't change
      handle_fetches(fourfour, order, row_count, page_size, current_page)
  end
end
```

### Testing and writing the join function
The [sort-merge-join](https://en.wikipedia.org/wiki/Sort-merge_join) approach for doing a join will work well for us, because we can request streams of socrata datasets in sorted order. (yes there are row limits let's pretend they don't exist for the sake of simplicity)

Let's write a test case that will help us test our join function. The join function will
take two streams which it will assume are in sorted order