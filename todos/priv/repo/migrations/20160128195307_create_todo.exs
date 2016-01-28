defmodule Todos.Repo.Migrations.CreateTodo do
  use Ecto.Migration

  def change do
    create table(:todos) do
      add :name, :string

      timestamps
    end

  end
end
