defmodule Todos.Todo do
  use Todos.Web, :model
  alias Todos.Todo
  alias Todos.Repo

  schema "todos" do
    field :name, :string

    timestamps
  end

  @required_fields ~w(name)
  @optional_fields ~w()

  @doc """
  Creates a changeset based on the `model` and `params`.

  If no params are provided, an invalid changeset is returned
  with no validation performed.
  """
  def changeset(model, params \\ :empty) do
    model
    |> cast(params, @required_fields, @optional_fields)
  end

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
end
