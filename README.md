# Fast Fuzzy Text Search In Phoenix With Ecto

<a href="http://cometa.works"><div alt="CometaWorks" style="text-align:center"><img src ="http://i.imgur.com/hYxiTro.png" /></div></a>

## Introduction
At CometaWorks, we have grown to adore [Elixir](http://www.elixir-lang.org) and [Phoenix](http://www.phoenixframework.org).
Recently, in a microservice we were building for a client, they required fuzzy text search.
With a fuzzy text search, loading the entirety of the columns we want to search into memory would be quite a heavy operation.
It makes much more sense to leverage the database to do the work.
In this post, we'll examine a way we were able to do this at the model level, without modifying Ecto or doing much more than writing a couple functions.

If you are already familiar with Phoenix in general, create an application, and generate a single model with a `name` field that is a string, and skip [here](https://github.com/cometaworks/fast_fuzzy_search_in_phoenix_and_ecto/blob/master/README.md#adding-search-to-our-model-enter-levenshtein) to save some time :)

## Getting Started
First off, let's generate a Phoenix application.
If you have not done this before, the [Phoenix Guides](http://www.phoenixframework.org/docs/overview) have a great walkthrough to get up and running.
Once you have gotten Phoenix, Elixir, and Erlang installer we can create our project using the `mix` build tool.
We will be building this purely as an API, but you can discard the `--no-brunch` flag if you wish to use Phoenix views.

```
$ mix phoenix.new todos --no-brunch
$ cd todos
$ mix do deps.get, compile, ecto.create
$ iex -S mix phoenix.server
```

Now, we've got a boilerplate application running and we can get started.

## Generating A Model
Now, in this simple application we are just going to make a `Todo` model with a single field: `name`.
To do this we just use another generator.

```
$ mix phoenix.gen.model Todo todos name:string
```

Now that we have a model, if we want to search anything we should have some of them in our database.
To do this, we'll use a nice little package known as `Faker`.
You can find it on github [here](https://github.com/igas/faker).
To add it to our project we just open up our `mix.exs` file and add it to our deps.

```
$ vi mix.exs
```

```elixir
..
  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [{:phoenix, "~> 1.1.2"},
     {:phoenix_ecto, "~> 2.0"},
     {:postgrex, ">= 0.0.0"},
     {:phoenix_html, "~> 2.3"},
     {:phoenix_live_reload, "~> 1.0", only: :dev},
     {:gettext, "~> 0.9"},
     {:cowboy, "~> 1.0"},
     {:faker, "~> 0.5"}] # simple, right?
  end
..
```

Now, we will have to grab this new dependency.

```
$ mix deps.get
```

And with this, we can set up some seeds for our database.

```
$ vi priv/repo/seeds.exs
```

```elixir
defmodule DatabaseSeeder do
  def add_random_todo do
    Todos.Repo.insert!(%Todos.Todo{name: Faker.Company.En.bullshit})
  end
end

Enum.each(1..1000, fn(n) -> add_random_todo end)
```

Now, we can seed our database with:

```
$ mix run priv/repo/seeds.exs
```

## Adding Search To Our Model: Enter Levenshtein
Wikipedia defines [Levenshtein Distance](https://en.wikipedia.org/wiki/Levenshtein_distance) as:

```
Informally, the Levenshtein distance between two words is the minimum number
of single-character edits (i.e. insertions, deletions or substitutions) required
to change one word into the other. It is named after Vladimir Levenshtein, who
considered this distance in 1965.
```

It just so happens that since version 9.1, Postgresql has supported this wonderful function.
To use it, we'll need to enable an extension first.
To do this, we just need to open up our database console.

```
$ psql
postgres# \c todos_dev
todos_dev# CREATE EXTENSION fuzzystrmatch;
todos_dev# \q
```

Now, we have enabled the `levenshtein` function.
But how do we use it?
We don't have any ability to access it directly through Ecto, and if we did we wouldn't be able to associate it with this model.
But we can fix that.
Let's open up `repo.ex`.

```
$ vi lib/todos/repo.ex
```

and we will see something like this:

```elixir
defmodule Todos.Repo do
  use Ecto.Repo, otp_app: :todos
end
```

Now, we will add a couple of functions to execute raw sql and then associate it with a model.

```elixir
..
  @doc """
A simple means to execute raw sql
Usage:

[record | _]Todos.Repo.execute_and_load("SELECT * FROM users WHERE id = $1", [1], Todo)
record
 => %Todo{...}
"""

  @spec execute_and_load(String.t, map(), __MODULE__) :: __MODULE__
  def execute_and_load(sql, params, model) do
    Ecto.Adapters.SQL.query!(__MODULE__, sql, params)
      |> load_into(model)
  end

  defp load_into(response, model) do
    Enum.map response.rows, fn(row) ->
      fields = Enum.reduce(Enum.zip(response.columns, row), %{}, fn({key, value}, map) ->
        Map.put(map, key, value)
      end)
      Ecto.Schema.__load__(model, nil, nil, [], fields, &__MODULE__.__adapter__.load/2)
    end
  end
..
```

This looks like a lot, but it really isn't.
Let's break it down starting with our private function `load_into/2`.

```elixir
def load_into(response, model) do
  Enum.map(response.rows, fn(row) ->
    ..
  end)
```

Starting here, we can simply see that whatever we take in for `response` is expected to be a list of sorts.
Note that we also pass in a `model`, in this case we want the model to be a struct like our `%Todo{}`.

```elixir
..
      fields = Enum.reduce(Enum.zip(response.columns, row), %{}, fn({key, value}, map) ->
        Map.put(map, key, value)
      end)
..
```

Don't be scared by the use of reduce and zip here.
Essentially, all we are doing is taking what amounts to a CSV (a list of columns names and values associated by index in more lists) and turning them into a series of `map` data structures.

```elixir
..
      Ecto.Schema.__load__(model, nil, nil, [], fields, &__MODULE__.__adapter__.load/2)
..
```

And now, last but not lease, we call `Ecto.Schema.__load__/6`.
What this does is it takes our map, and puts our new values into a struct that is a `%Todos.Todo{}` struct, so that we are dealing with our own model again.

Now, on to `execute_and_load/3`:

```elixir
..
    Ecto.Adapters.SQL.query!(__MODULE__, sql, params)
      |> load_into(model)
..
```

This part is a bit easier on the eyes.
`__MODULE__` expants into the name of the current module name as an atom type.

`sql` is a sql query expected as a string.

`params` is simply a map of parameters.

Now, to see it in action:

```elixir
$ iex -S mix
iex(1)> Todos.Repo.insert(%Todo{name: "stuff"})
iex(2)> alias Todos.Todo
iex(3)> alias Todos.Repo
iex(4)> [todo|_]= Repo.execute_and_load("SELECT * FROM todos;", [], Todo)
iex(5)> todo
%Todos.Todo{__meta__: #Ecto.Schema.Metadata<:loaded>, id: 1,
 inserted_at: #Ecto.DateTime<2016-01-28T20:01:44Z>, name: "stuff",
  updated_at: #Ecto.DateTime<2016-01-28T20:01:44Z>}
```

So now we can load a model in from raw SQL and execute whatever we want inside.
Now its time so add some fuzzy search.
But first, let's experiment with it a bit and learn what we will be utilizing.

## Using The Levenshtein Function
Let's fire up `psql` and play a bit.

```
$ psql
postgres# \c todos_dev
todos_dev=# SELECT levenshtein('ABC', 'ABCD');
levenshtein
-------------
           1
(1 row)
```

Since it would take 1 more character to become the string `ABCD`, we get the output `1`.

We can reverse the arguments, too:

```
todos_dev=# SELECT levenshtein('ABCD', 'ABC');
levenshtein
-------------
           1
(1 row)
```

## Implementing It In Our Model
Now, we can add this functionality to our model quite easily with the help of the functions we wrote earlier in `lib/todos/repo.ex`.

```
$ vi web/models/todo.ex
```

```elixir
...
  alias Todos.Todo
  alias Todos.Repo
  def fuzzy_name_search(query_string) do
    query = """
SELECT *
FROM todos
WHERE levenshtein(name, $1) < 5
ORDER BY levenshtein(name, $1)
LIMIT 10;
"""
    query
    |> Repo.execute_and_load([query_string], Todo)
  end
...
```

Let's break this down like we have the rest of these code snippets.

First, we set up a basic `SELECT` query.
We also alias the modules `Todo` and `Repo` for simple access.
Now, we want to find all the matches of where our levenshtein distance is less than the first variable we have given.
In our `execute_and_load/3` function, the second argument is a filler variable to be used in SQL.

So we pipe the query in there, with our parameters of the string we want to match, and the model we want to map it to coming out, and now with `load_into/2` we are good to go.

## Testing It Out
Let's use our new function in IEx to test is out.

```elixir
$ iex -S mix
iex(1)> alias Todos.Todo
iex(2)> Todo.fuzzy_name_search("custom")
[debug] SELECT *
FROM todos
WHERE levenshtein(name, $1) < 5
ORDER BY levenshtein(name, $1)
LIMIT 10;
 ["custom"] OK query=114.9ms queue=16.6ms
[%Todos.Todo{__meta__: #Ecto.Schema.Metadata<:loaded>, id: 1,
  inserted_at: #Ecto.DateTime<2016-01-28T20:01:44Z>, name: "customized",
  updated_at: #Ecto.DateTime<2016-01-28T20:01:44Z>},
 %Todos.Todo{__meta__: #Ecto.Schema.Metadata<:loaded>, id: 29,
  inserted_at: #Ecto.DateTime<2016-01-28T20:01:44Z>, name: "customized",
  updated_at: #Ecto.DateTime<2016-01-28T20:01:44Z>},
 %Todos.Todo{__meta__: #Ecto.Schema.Metadata<:loaded>, id: 42,
  inserted_at: #Ecto.DateTime<2016-01-28T20:01:44Z>, name: "customized",
  updated_at: #Ecto.DateTime<2016-01-28T20:01:44Z>},
 %Todos.Todo{__meta__: #Ecto.Schema.Metadata<:loaded>, id: 88,
  inserted_at: #Ecto.DateTime<2016-01-28T20:01:44Z>, name: "customized",
  updated_at: #Ecto.DateTime<2016-01-28T20:01:44Z>},
 %Todos.Todo{__meta__: #Ecto.Schema.Metadata<:loaded>, id: 114,
  inserted_at: #Ecto.DateTime<2016-01-28T20:01:44Z>, name: "customized",
  updated_at: #Ecto.DateTime<2016-01-28T20:01:44Z>},
 %Todos.Todo{__meta__: #Ecto.Schema.Metadata<:loaded>, id: 141,
  inserted_at: #Ecto.DateTime<2016-01-28T20:01:44Z>, name: "customized",
  updated_at: #Ecto.DateTime<2016-01-28T20:01:44Z>},
 %Todos.Todo{__meta__: #Ecto.Schema.Metadata<:loaded>, id: 302,
  inserted_at: #Ecto.DateTime<2016-01-28T20:01:45Z>, name: "customized",
  updated_at: #Ecto.DateTime<2016-01-28T20:01:45Z>},
 %Todos.Todo{__meta__: #Ecto.Schema.Metadata<:loaded>, id: 378,
  inserted_at: #Ecto.DateTime<2016-01-28T20:01:45Z>, name: "customized",
  updated_at: #Ecto.DateTime<2016-01-28T20:01:45Z>},
 %Todos.Todo{__meta__: #Ecto.Schema.Metadata<:loaded>, id: 430,
  inserted_at: #Ecto.DateTime<2016-01-28T20:01:45Z>, name: "customized",
  updated_at: #Ecto.DateTime<2016-01-28T20:01:45Z>},
 %Todos.Todo{__meta__: #Ecto.Schema.Metadata<:loaded>, id: 508,
  inserted_at: #Ecto.DateTime<2016-01-28T20:01:45Z>, name: "customized",
  updated_at: #Ecto.DateTime<2016-01-28T20:01:45Z>}]
```

Boom, we have success.

If you enjoyed this, follow me on [Twitter](https://twitter.com/yburyug).

The code is available on [Github](https://github.com/cometaworks/fast_fuzzy_search_in_phoenix_and_ecto)

And if you'd like to have some design, software craftsmanship, or other general tech needs feel free to give us a buzz at

<a href="http://cometa.works"><div alt="CometaWorks" style="text-align:center"><img src ="http://i.imgur.com/hYxiTro.png" /></div></a>
