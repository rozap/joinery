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

#### Configuration
In your `config/config.exs`, `exsoda` wants a domain, so we shall abide. Let's use `data.austintexas.gov` as our domain because they have cool datasets.
```elixir
config :exsoda,
  domain: "data.austintexas.gov"
```

First we'll need to get the rows out of the soda store. Because we don't want to
load all the rows into memory and we don't want long lived connections, we'll need to request batches of rows, which will imply some sort of state living somewhere. In Elixir/Erlang, all state is explicitly held by processes. This means the only way you can get at the state is by sending a message to that process. Because a process can only read one message at a time, this ensures that access to state is synchronized.

The idea behind state in elixir is to have a function recursively call itself, where the body of the function executes a `receive` block to handle a message in its mailbox. The function can then react to that message in any way it wants, and then it can call itself with the new state, causing it to wait for the next message.

Let's start by making a module called `Joinery.Pager` in `joinery/pager.ex` and a test module called `test/pager_test.exs`

```elixir
defmodule Joinery.Pager do
  import Exsoda.Reader
end
```

Our `Pager` module is going to have just two external functions, `start/3` and `next/1`. `start` will take the four-four, row ordering, and page size, and it will start a new process which will accept messages and then call itself recursively. `next/1` will take the pid of that process and will send a message to advance the page, then wait for a reply with the rows that it got.

We can write some really simple tests like this in `test/pager_test.exs`
```elixir
defmodule PagerTest do
  use ExUnit.Case
  alias Joinery.Pager

  test "can get the first page" do
    # Yep we're testing on live datasets - not a great
    # idea, but if this call fails then we all probably
    # have much more important stuff to be dealing with
    # right now anyway...
    {:ok, pager_pid} = Pager.start("hcnj-rei3", 5)

    {:ok, rows} = Pager.next(pager_pid)
    assert length(rows) == 5
  end

  test "can get the second page" do
    {:ok, lil_pager} = Pager.start("hcnj-rei3", 5)

    {:ok, first} = Pager.next(lil_pager)
    {:ok, second} = Pager.next(lil_pager)

    {:ok, big_pager} = Pager.start("hcnj-rei3", 10)
    {:ok, all} = Pager.next(big_pager)

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

So now your tests should pass. [If they don't, this is the implementation that I came up with](https://github.com/rozap/joinery/blob/master/lib/joinery/pager.ex)

### Writing an HTTP Service

We're going to use [plug](https://github.com/elixir-lang/plug) which is a specification for writing http connection handlers in elixir. The phoenix framework is based on plug, so they behave very similarly, but plug is "lower level".

Plug (and the core of phoenix) is pretty simple. A plug is just a module that has two functions, `init/1` and `call/2`.
  * `init/1` returns any options for that plug
  * `call/2` takes a connection, and must return a new connection, with any transformations applied. It's important to remember that connections are immutable, so:

  ```elixir
    # very bad - `conn` is still bound to the same `conn` that was passed in
    def call(conn, _) do
      put_resp_content_type(conn, "text/plain")]
      send_resp(conn, 200, "ok")
      send_resp(conn, 200, "ok")

      conn
    end
  ```

  ```elixir
    # better
    def call(conn, _) do
      conn = put_resp_content_type(conn, "text/plain")]
      conn = send_resp(conn, 200, "ok")
      conn
    end
  ```
See in the second one, we return a new `conn` struct for everything we do on the struct?

This works as well
  ```elixir
    # With syntactic sugar
    def call(conn, _) do
      conn
      |> put_resp_content_type("text/plain")]
      |> send_resp(200, "ok")
    end
  ```
This is the same as the previous example, but since pretty much all the methods in the plug library take a conn as the first argument, the `|>` operator works well for getting rid of all the variable rebinding, which can get a little confusing.

Now we can write some stuff. First will add some dependencies. Add `{:cowboy, "~> 1.0.0"}` and `{:plug, "~> 1.0"}` the the deps in our mixfile. Cowboy is an http server written in erlang. Run `mix deps.get` to fetch the new dependencies.

Now we'll write a test for our plug. I made a file called `test/http_test.exs`. It's just going to look like a normal `ExUnit` test module, but we're going to `use` the `Plug.Test` module. `use` is a macro that pulls in certain attributes defined by the module.

```elixir
defmodule HttpTest do
  use ExUnit.Case, async: true
  use Plug.Test

  # Just so we can refer to our router as `Router` instead of `Joinery.Router`
  alias Joinery.Router

  @opts Router.init([])
end
```

Now we can write a plug test. This looks like a normal `ExUnit` test.

```elixir
test "returns hello world" do
  conn = conn(:get, "/hello")

  # Invoke the plug
  conn = Router.call(conn, @opts)

  assert conn.state == :sent
  assert conn.status == 200
  assert conn.resp_body == "world"
end
```

Now try running `mix test test/http_test.exs` and you should get a `Joinery.Router` not defined error, so let's go write that module.

I made a file called `lib/joinery/router.ex`, and it has a bit of plug boilerplate in it. We're using the Plug.Router which turns our module into a

```elixir
defmodule Joinery.Router do
  use Plug.Router

  plug :match
  plug :dispatch

end
```

Now we can write a route for the `/hello` path that we wrote in the test. It will look like
```elixir
  get "/hello" do
    send_resp(conn, 200, "world")
  end
```

We also want to handle unknown routes,
```elixir
  match _ do
    send_resp(conn, 404, "idk")
  end
```

So now our router should look like

```elixir
defmodule Joinery.Router do
  use Plug.Router
  require Logger

  plug :match
  plug :dispatch

  get "/hello" do
    send_resp(conn, 200, "world")
  end

  match _ do
    send_resp(conn, 404, "idk")
  end
end

```

Now try running `mix test test/http_test.exs` and things should pass.

### The `Application`
At this point we have a test, but we need to add our plug to our `Application` if we actually want to run it. An Application is something that can be started or stopped as a unit, and potentially re-used in other applications. Our `Application` consists of an HTTP Server, but it could also have other things, like activemq consumers, workers, metrics gatherers, etc. An elixir/erlang Application differs from the "we're starting this {ruby|python|java} application now, spawn a bunch of threads to do different things and hopefully they don't crash" strategy by defining a supervision tree which can be started or stopped, and can restart any children when they misbehave.

Right now we have an empty module called `Joinery` in `lib/joinery.ex`. This will be our application module. Let's make it our entry point. We need to `use Application` and defint a `start/2` function.

```elixir
defmodule Joinery do
  # make this module an application
  use Application
  # we're going to log stuff, so pull in the Logger module
  require Logger

  def start(_type, _args) do
    Logger.info("Starting our app!")
  end
end
```

We also need to tell `mix` which module is our application. Notice there is an `application/0` function in our mixfile (`mix.exs`). While you're at it, go ahead and add `:cowboy` and `:plug` to the `applications` list, which will tell erlang to start those applications when the `Joinery` app starts.

```elixir
  def application do
    [
      mod: {Joinery, []}, # Tell mix that this is our entrypoint
      applications: [:logger, :exsoda, :cowboy, :plug]
    ]
  end
```

Now start our app with `iex -S mix`

Our app should log `Starting our app!` and then it will crash with
```
** (Mix) Could not start application joinery: Joinery.start(:normal, []) returned a bad value: :ok
```

This is because we didn't start an Application supervisor and return it, which is required.
```elixir
defmodule Joinery do
  use Application
  require Logger

  @port 4000

  def start(_type, _args) do
    Logger.info("Starting our app!")
    import Supervisor.Spec

    child_specs = [
      # Plug can adapt our Router plug to a child specification that
      # we can then give to a supervisor. A child specification is something
      # that says how we start something, and how we restart it when it crashes
      Plug.Adapters.Cowboy.child_spec(:http, Joinery.Router, [], [port: @port])
    ]

    Logger.info("Starting on port #{@port}")

    # start_link starts our supervisor with our child_specs
    Supervisor.start_link(
      child_specs,
      # We give it a name, so when you start observer you can identify it easily
      strategy: :one_for_one, name: Joinery.Supervisor
    )
  end
end
```

Now start the app with `iex -S mix`, and you should see that it started. Now go to `http://localhost:4000` in your browser, and you should get a very helpful 404 message. Similarly `http://localhost:4000/hello` should work.


### Writing a `/join` route
We don't have enough time to actually implement the merge-join function, so there's an implementation here https://github.com/rozap/joinery/blob/master/lib/joinery/join.ex . Copy it into your project as `lib/joinery/join.ex`. We'll be using the `join/4` function shortly.

My route is going to look like `/join/left-four.foo/rite-four.bar`

which will do something like `SELECT * FROM left-four lf INNER JOIN rite-four rf ON lf.foo = rf.bar`

We're basically going to do the same thing as our tests...

```elixir
  defp split_ff_column(url) do
    # Write a function that splits "four-four.zip_code"
    # into {:ok, "four-four", "zip_code"} or {:error, "some reason"}
    # if it fails
  end

  defp display_name_to_field_name(four_four, display_name) do
    # Write a function that maps something like "Zip Code" to the view's Soda2
    # column like `zip_code`. Since we require the SoQL `sort` to use the
    # field_name but then give back the display_name in the response, we need
    # to have tell the pager to sort by `zip_code` and then join on `Zip Code`

    # Hint: use Exsoda.Reader.get_view to get the view+columns
    # https://github.com/rozap/exsoda#get-a-view
  end

  get "/join/:left/:right" do
    result = with {:ok, left_ff, left_j} <- to_fourfour_join(left),
      {:ok, right_ff, right_j} <- to_fourfour_join(right),
      {:ok, left_field_name} <- display_name_to_field_name(left_ff, left_j),
      {:ok, right_field_name} <- display_name_to_field_name(right_ff, right_j) do

      Logger.info("Planning to join #{left_ff}.#{left_j} (#{left_field_name}) to #{right_ff}.#{right_j} (#{right_field_name})")

      {:ok, left} = Joinery.Pager.start(left_ff, left_field_name)
      {:ok, right} = Joinery.Pager.start(right_ff, right_field_name)

      response = Joinery.Join.join(left, right, left_j, right_j)
      # Since our join/4 function gives back keyword lists, we
      # need to change those keyword lists into Maps.
      # Enum.into(a_keylist, %{}) converts a keylist into a map
      |> Enum.map(fn keylist -> Enum.into(keylist, %{}) end)
      # Encode our list of maps as json
      |> Poison.encode!

      # Write all of them to the connection, give back a new connection
      send_resp(conn, 200, response)
    end

    with {:error, reason} <- result do
      send_resp(conn, 400, reason)
    end
  end
```

Given that we already had all the pieces, hooking it up to an HTTP endpoint was pretty straight forward. Try killing and restarting your iex session, with `iex -S mix` and go to `http://localhost:4000/join/hcnj-rei3.Zip Code/32y8-3gbr.Zip Code`

Woohoo!

### Fixing other people's crappy code.
Your coworker Kristoff is kind of an idiot and now your service is falling over because he wrote the `join.ex` in a naive way. He wrote a `TODO` in 2009 and then never fixed it, but at least you know where it is, and knowing is half the battle. There are two problems with it - it concatenates lists together needlessly, and it's eager, so the whole joined dataset is loaded into memory.

Can you think of a way to solve both of these problems?

Hints:
  * Instead of returning a list from do_join, spawn a process that does the join, and then in our own process, listen for results and wrap the receive in
  a stream

  Example:

  ```
  def join(blah, blah, blah, blah) do

    # Pass the received to the do_join function so it can send stuff to it
    owner = self()
    joiner = spawn_link(fn ->
      # do_join will now need to send {:rows, the_rows, self()}
      # messages back to the owner process, and will need to
      # send a :done message when it's done
      do_join(%State{owner: owner})
    end)

    Stream.resource(
      fn -> :ok,
      fn state ->
        receive do
          {:rows, rows, ^owner} -> {rows, state}
          :done -> {:halt, state}
        end
      end,
      fn _ -> :ok
    )
  end

