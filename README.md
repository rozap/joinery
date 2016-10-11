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

### Testing and writing the join function
The [sort-merge-join](https://en.wikipedia.org/wiki/Sort-merge_join) approach for doing a join will work well for us, because we can request streams of socrata datasets in sorted order. (yes there are row limits let's pretend they don't exist for the sake of simplicity)

Let's write a test case that will help us test our join function. The join function will
take two streams which it will assume are in sorted order